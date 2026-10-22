/* Link cable over Wi-Fi. Spec: docs/specs/link-cable.md */
#if !defined(_WIN32) && !defined(_GNU_SOURCE)
#define _GNU_SOURCE
#endif
#include "dena/link.h"

#include <string.h>

#if defined(_WIN32)

/* The PC build only runs the harness; the link needs a phone or handheld. */
int dena_link_host(int port, const char *name) { (void)port, (void)name; return -1; }
int dena_link_join(const char *address, int port) { (void)address, (void)port; return -1; }
void dena_link_stop(void) {}
int dena_link_state(void) { return DENA_LINK_OFF; }
int dena_link_role(void) { return DENA_LINK_PARENT; }
const char *dena_link_error(void) { return "link cable is not supported on Windows"; }
const char *dena_link_peer(void) { return ""; }
int dena_link_scan_start(void) { return -1; }
void dena_link_scan_stop(void) {}
int dena_link_scan_results(char *out, int len) { if (len > 0) out[0] = 0; return 0; }
int dena_link_local_address(char *out, int len) { if (len > 0) out[0] = 0; return 0; }
const struct dena_link_api *dena_link_core_api(void) { return NULL; }

#else

#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <netdb.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <poll.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

#define MSG_SIZE 8
#define MSG_MAGIC 'D'
#define MSG_HELLO 0x01
#define INBOX_CAP 256
#define SCAN_MAX 16
#define SCAN_TTL_MS 3000

typedef struct {
  uint8_t kind;
  uint32_t value;
} msg;

static pthread_mutex_t g_lock = PTHREAD_MUTEX_INITIALIZER;   /* state below */
static pthread_mutex_t g_send = PTHREAD_MUTEX_INITIALIZER;   /* socket writes */
static pthread_cond_t g_inbox_cond = PTHREAD_COND_INITIALIZER;

static atomic_int g_state = DENA_LINK_OFF;
static atomic_int g_role = DENA_LINK_PARENT;
static atomic_int g_sock = -1;    /* connected peer */
static atomic_int g_listen = -1;  /* hosting only */
static atomic_int g_stop = 0;
static pthread_t g_thread, g_beacon_thread;
static int g_thread_live, g_beacon_live;
static char g_error[160];
static char g_peer[64];
static char g_name[64];
static char g_join_addr[256];
static int g_port;

static msg g_inbox[INBOX_CAP];
static unsigned g_head, g_tail;   /* under g_lock */
static atomic_uint g_pending;     /* lock-free emptiness check for polls */

static void set_error(const char *what) {
  pthread_mutex_lock(&g_lock);
  snprintf(g_error, sizeof g_error, "%s%s%s", what, errno ? ": " : "", errno ? strerror(errno) : "");
  pthread_mutex_unlock(&g_lock);
}

static uint64_t now_ms(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (uint64_t)ts.tv_sec * 1000u + (uint64_t)ts.tv_nsec / 1000000u;
}

static int write_all(int fd, const uint8_t *buf, size_t n) {
  while (n) {
    ssize_t w = send(fd, buf, n, MSG_NOSIGNAL);
    if (w < 0 && errno == EINTR) continue;
    if (w <= 0) return -1;
    buf += w;
    n -= (size_t)w;
  }
  return 0;
}

static int send_msg(int fd, uint8_t kind, uint32_t value) {
  uint8_t b[MSG_SIZE] = {MSG_MAGIC, kind, 0, 0,
                         (uint8_t)(value >> 24), (uint8_t)(value >> 16),
                         (uint8_t)(value >> 8), (uint8_t)value};
  pthread_mutex_lock(&g_send);
  int r = write_all(fd, b, sizeof b);
  pthread_mutex_unlock(&g_send);
  return r;
}

/* Reads one message, waiting at most timeout_ms (-1 forever) for it to
 * start. Returns 1, 0 on timeout, -1 on a closed or broken connection. */
static int read_msg(int fd, msg *out, int timeout_ms) {
  uint8_t b[MSG_SIZE];
  size_t got = 0;
  while (got < sizeof b) {
    struct pollfd p = {fd, POLLIN, 0};
    int r = poll(&p, 1, got ? 1000 : timeout_ms);
    if (r < 0 && errno == EINTR) continue;
    if (r < 0) return -1;
    if (r == 0) {
      if (!got) return 0;
      return -1; /* half a message for a second: broken peer */
    }
    ssize_t n = recv(fd, b + got, sizeof b - got, 0);
    if (n < 0 && errno == EINTR) continue;
    if (n <= 0) return -1;
    got += (size_t)n;
  }
  if (b[0] != MSG_MAGIC) return -1;
  out->kind = b[1];
  out->value = ((uint32_t)b[4] << 24) | ((uint32_t)b[5] << 16) | ((uint32_t)b[6] << 8) | b[7];
  return 1;
}

static void inbox_clear(void) {
  pthread_mutex_lock(&g_lock);
  g_head = g_tail = 0;
  atomic_store(&g_pending, 0);
  pthread_cond_broadcast(&g_inbox_cond);
  pthread_mutex_unlock(&g_lock);
}

static void inbox_push(msg m) {
  pthread_mutex_lock(&g_lock);
  if (g_tail - g_head < INBOX_CAP) {
    g_inbox[g_tail++ % INBOX_CAP] = m;
    atomic_fetch_add(&g_pending, 1);
  }
  pthread_cond_signal(&g_inbox_cond);
  pthread_mutex_unlock(&g_lock);
}

static void tune_socket(int fd) {
  int one = 1;
  setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof one);
}

static void set_peer(const struct sockaddr_in *a) {
  pthread_mutex_lock(&g_lock);
  inet_ntop(AF_INET, &a->sin_addr, g_peer, sizeof g_peer);
  pthread_mutex_unlock(&g_lock);
}

/* Both sides say hello first, so a stray connection never reaches a core. */
static int handshake(int fd) {
  if (send_msg(fd, MSG_HELLO, DENA_LINK_API_VERSION) < 0) return -1;
  msg m;
  if (read_msg(fd, &m, 5000) != 1 || m.kind != MSG_HELLO) {
    errno = 0;
    set_error("the other device did not answer as Dena.emu");
    return -1;
  }
  if (m.value != DENA_LINK_API_VERSION) {
    errno = 0;
    set_error("the other device runs a different Dena.emu version");
    return -1;
  }
  return 0;
}

static int connect_to(const char *address, int port) {
  char service[16];
  snprintf(service, sizeof service, "%d", port);
  struct addrinfo hints, *res = NULL;
  memset(&hints, 0, sizeof hints);
  hints.ai_family = AF_INET;
  hints.ai_socktype = SOCK_STREAM;
  if (getaddrinfo(address, service, &hints, &res) != 0 || !res) {
    errno = 0;
    set_error("cannot resolve that address");
    return -1;
  }
  /* Non-blocking connect, so dena_link_stop() never waits on the OS timeout. */
  int fd = socket(AF_INET, SOCK_STREAM, 0);
  int ok = 0;
  if (fd >= 0) {
    int flags = fcntl(fd, F_GETFL, 0);
    fcntl(fd, F_SETFL, flags | O_NONBLOCK);
    if (connect(fd, res->ai_addr, res->ai_addrlen) == 0) {
      ok = 1;
    } else if (errno == EINPROGRESS) {
      for (int waited = 0; waited < 5000 && !atomic_load(&g_stop) && !ok; waited += 200) {
        struct pollfd p = {fd, POLLOUT, 0};
        if (poll(&p, 1, 200) <= 0) continue;
        int err = 0;
        socklen_t el = sizeof err;
        getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &el);
        errno = err;
        ok = err == 0;
        if (!ok) break;
      }
      if (!ok && errno == EINPROGRESS) errno = ETIMEDOUT;
    }
    fcntl(fd, F_SETFL, flags);
  }
  if (!ok) {
    set_error("cannot connect");
    if (fd >= 0) close(fd);
    freeaddrinfo(res);
    return -1;
  }
  set_peer((const struct sockaddr_in *)res->ai_addr);
  freeaddrinfo(res);
  return fd;
}

static void *link_thread(void *arg) {
  (void)arg;
  int fd = -1;
  if (atomic_load(&g_role) == DENA_LINK_PARENT) {
    int lfd = atomic_load(&g_listen);
    while (!atomic_load(&g_stop) && fd < 0) {
      struct pollfd p = {lfd, POLLIN, 0};
      if (poll(&p, 1, 200) <= 0) continue;
      struct sockaddr_in a;
      socklen_t al = sizeof a;
      fd = accept(lfd, (struct sockaddr *)&a, &al);
      if (fd >= 0) set_peer(&a);
    }
  } else {
    fd = connect_to(g_join_addr, g_port);
  }
  if (fd >= 0 && !atomic_load(&g_stop)) {
    tune_socket(fd);
    if (handshake(fd) == 0) {
      inbox_clear();
      atomic_store(&g_sock, fd);
      atomic_store(&g_state, DENA_LINK_CONNECTED);
      msg m;
      int r;
      while (!atomic_load(&g_stop) && (r = read_msg(fd, &m, 200)) >= 0) {
        if (r == 1 && m.kind != MSG_HELLO) inbox_push(m);
      }
      if (!atomic_load(&g_stop)) {
        errno = 0;
        set_error("the other device disconnected");
      }
      atomic_store(&g_sock, -1);
    }
  }
  if (fd >= 0) close(fd);
  if (!atomic_load(&g_stop)) atomic_store(&g_state, DENA_LINK_FAILED);
  pthread_mutex_lock(&g_lock);
  pthread_cond_broadcast(&g_inbox_cond);
  pthread_mutex_unlock(&g_lock);
  return NULL;
}

static void *beacon_thread(void *arg) {
  (void)arg;
  int fd = socket(AF_INET, SOCK_DGRAM, 0);
  if (fd < 0) return NULL;
  int one = 1;
  setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &one, sizeof one);
  struct sockaddr_in to;
  memset(&to, 0, sizeof to);
  to.sin_family = AF_INET;
  to.sin_port = htons(DENA_LINK_BEACON_PORT);
  to.sin_addr.s_addr = htonl(INADDR_BROADCAST);
  char payload[128];
  snprintf(payload, sizeof payload, "DENALINK%d %d %s", DENA_LINK_API_VERSION, g_port, g_name);
  while (!atomic_load(&g_stop) && atomic_load(&g_state) == DENA_LINK_WAITING) {
    sendto(fd, payload, strlen(payload), 0, (struct sockaddr *)&to, sizeof to);
    for (int i = 0; i < 10 && !atomic_load(&g_stop); i++) usleep(100 * 1000);
  }
  close(fd);
  return NULL;
}

void dena_link_stop(void) {
  atomic_store(&g_stop, 1);
  int lfd = atomic_exchange(&g_listen, -1);
  int fd = atomic_load(&g_sock);
  if (fd >= 0) shutdown(fd, SHUT_RDWR);
  if (g_thread_live) pthread_join(g_thread, NULL);
  if (g_beacon_live) pthread_join(g_beacon_thread, NULL);
  g_thread_live = g_beacon_live = 0;
  if (lfd >= 0) close(lfd);
  atomic_store(&g_sock, -1);
  atomic_store(&g_state, DENA_LINK_OFF);
  atomic_store(&g_stop, 0);
  inbox_clear();
  pthread_mutex_lock(&g_lock);
  g_error[0] = g_peer[0] = 0;
  pthread_mutex_unlock(&g_lock);
}

static int start(int role) {
  atomic_store(&g_role, role);
  atomic_store(&g_state, DENA_LINK_WAITING);
  if (pthread_create(&g_thread, NULL, link_thread, NULL) != 0) {
    set_error("cannot start the link thread");
    atomic_store(&g_state, DENA_LINK_FAILED);
    return -1;
  }
  g_thread_live = 1;
  return 0;
}

int dena_link_host(int port, const char *name) {
  dena_link_stop();
  g_port = port > 0 ? port : DENA_LINK_PORT;
  snprintf(g_name, sizeof g_name, "%s", name && *name ? name : "Dena.emu");
  for (char *c = g_name; *c; c++) if (*c == '\t' || *c == '\n') *c = ' ';
  int lfd = socket(AF_INET, SOCK_STREAM, 0);
  int one = 1;
  struct sockaddr_in a;
  memset(&a, 0, sizeof a);
  a.sin_family = AF_INET;
  a.sin_port = htons((uint16_t)g_port);
  a.sin_addr.s_addr = htonl(INADDR_ANY);
  if (lfd < 0 || setsockopt(lfd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one) < 0 ||
      bind(lfd, (struct sockaddr *)&a, sizeof a) < 0 || listen(lfd, 1) < 0) {
    set_error("cannot open the link port");
    if (lfd >= 0) close(lfd);
    atomic_store(&g_state, DENA_LINK_FAILED);
    return -1;
  }
  atomic_store(&g_listen, lfd);
  if (start(DENA_LINK_PARENT) < 0) return -1;
  if (pthread_create(&g_beacon_thread, NULL, beacon_thread, NULL) == 0) g_beacon_live = 1;
  return 0;
}

int dena_link_join(const char *address, int port) {
  dena_link_stop();
  if (!address || !*address) {
    errno = 0;
    set_error("no address");
    atomic_store(&g_state, DENA_LINK_FAILED);
    return -1;
  }
  snprintf(g_join_addr, sizeof g_join_addr, "%s", address);
  g_port = port > 0 ? port : DENA_LINK_PORT;
  return start(DENA_LINK_CHILD);
}

int dena_link_state(void) { return atomic_load(&g_state); }
int dena_link_role(void) { return atomic_load(&g_role); }

const char *dena_link_error(void) {
  static char copy[sizeof g_error];
  pthread_mutex_lock(&g_lock);
  memcpy(copy, g_error, sizeof copy);
  pthread_mutex_unlock(&g_lock);
  return copy;
}

const char *dena_link_peer(void) {
  static char copy[sizeof g_peer];
  pthread_mutex_lock(&g_lock);
  memcpy(copy, g_peer, sizeof copy);
  pthread_mutex_unlock(&g_lock);
  return copy;
}

/* --- Discovery --- */

typedef struct {
  char name[64];
  char addr[64];
  int port;
  uint64_t seen;
} scan_entry;

static pthread_mutex_t g_scan_lock = PTHREAD_MUTEX_INITIALIZER;
static scan_entry g_scan[SCAN_MAX];
static pthread_t g_scan_thread;
static int g_scan_live;
static atomic_int g_scan_stop;

static void *scan_thread(void *arg) {
  int fd = (int)(intptr_t)arg;
  while (!atomic_load(&g_scan_stop)) {
    struct pollfd p = {fd, POLLIN, 0};
    if (poll(&p, 1, 200) <= 0) continue;
    char buf[160];
    struct sockaddr_in from;
    socklen_t fl = sizeof from;
    ssize_t n = recvfrom(fd, buf, sizeof buf - 1, 0, (struct sockaddr *)&from, &fl);
    if (n <= 0) continue;
    buf[n] = 0;
    int version = 0, port = 0, used = 0;
    if (sscanf(buf, "DENALINK%d %d %n", &version, &port, &used) < 2 || !used) continue;
    if (version != DENA_LINK_API_VERSION || port <= 0 || port > 65535) continue;
    char addr[64];
    inet_ntop(AF_INET, &from.sin_addr, addr, sizeof addr);
    uint64_t t = now_ms();
    pthread_mutex_lock(&g_scan_lock);
    int slot = -1;
    for (int i = 0; i < SCAN_MAX; i++) {
      if (g_scan[i].seen && !strcmp(g_scan[i].addr, addr) && g_scan[i].port == port) { slot = i; break; }
    }
    for (int i = 0; slot < 0 && i < SCAN_MAX; i++) {
      if (!g_scan[i].seen || t - g_scan[i].seen > SCAN_TTL_MS) slot = i;
    }
    if (slot >= 0) {
      snprintf(g_scan[slot].name, sizeof g_scan[slot].name, "%s", buf + used);
      snprintf(g_scan[slot].addr, sizeof g_scan[slot].addr, "%s", addr);
      g_scan[slot].port = port;
      g_scan[slot].seen = t;
    }
    pthread_mutex_unlock(&g_scan_lock);
  }
  close(fd);
  return NULL;
}

int dena_link_scan_start(void) {
  dena_link_scan_stop();
  int fd = socket(AF_INET, SOCK_DGRAM, 0);
  int one = 1;
  struct sockaddr_in a;
  memset(&a, 0, sizeof a);
  a.sin_family = AF_INET;
  a.sin_port = htons(DENA_LINK_BEACON_PORT);
  a.sin_addr.s_addr = htonl(INADDR_ANY);
  if (fd < 0 || setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one) < 0 ||
      bind(fd, (struct sockaddr *)&a, sizeof a) < 0) {
    if (fd >= 0) close(fd);
    return -1;
  }
  atomic_store(&g_scan_stop, 0);
  if (pthread_create(&g_scan_thread, NULL, scan_thread, (void *)(intptr_t)fd) != 0) {
    close(fd);
    return -1;
  }
  g_scan_live = 1;
  return 0;
}

void dena_link_scan_stop(void) {
  if (!g_scan_live) return;
  atomic_store(&g_scan_stop, 1);
  pthread_join(g_scan_thread, NULL);
  g_scan_live = 0;
  pthread_mutex_lock(&g_scan_lock);
  memset(g_scan, 0, sizeof g_scan);
  pthread_mutex_unlock(&g_scan_lock);
}

int dena_link_scan_results(char *out, int len) {
  if (!out || len <= 0) return 0;
  out[0] = 0;
  int used = 0;
  uint64_t t = now_ms();
  pthread_mutex_lock(&g_scan_lock);
  for (int i = 0; i < SCAN_MAX; i++) {
    if (!g_scan[i].seen || t - g_scan[i].seen > SCAN_TTL_MS) continue;
    int n = snprintf(out + used, (size_t)(len - used), "%s\t%s\t%d\n", g_scan[i].name,
                     g_scan[i].addr, g_scan[i].port);
    if (n < 0 || n >= len - used) { out[used] = 0; break; }
    used += n;
  }
  pthread_mutex_unlock(&g_scan_lock);
  return used;
}

int dena_link_local_address(char *out, int len) {
  if (!out || len <= 0) return 0;
  out[0] = 0;
  struct ifaddrs *list = NULL;
  if (getifaddrs(&list) != 0) return 0;
  int best = 0; /* 2 = a wlan interface, 1 = any other */
  for (struct ifaddrs *i = list; i; i = i->ifa_next) {
    if (!i->ifa_addr || i->ifa_addr->sa_family != AF_INET) continue;
    if (!(i->ifa_flags & IFF_UP) || (i->ifa_flags & IFF_LOOPBACK)) continue;
    int score = strncmp(i->ifa_name, "wlan", 4) == 0 ? 2 : 1;
    if (score <= best) continue;
    inet_ntop(AF_INET, &((struct sockaddr_in *)i->ifa_addr)->sin_addr, out, (socklen_t)len);
    best = score;
  }
  freeifaddrs(list);
  return (int)strlen(out);
}

/* --- Core transport --- */

static int api_connected(void *user) {
  (void)user;
  return atomic_load(&g_state) == DENA_LINK_CONNECTED;
}

static int api_role(void *user) {
  (void)user;
  return atomic_load(&g_role);
}

static int api_send(void *user, uint8_t kind, uint32_t value) {
  (void)user;
  int fd = atomic_load(&g_sock);
  if (fd < 0 || kind == MSG_HELLO) return -1;
  return send_msg(fd, kind, value);
}

static int api_recv(void *user, uint8_t *kind, uint32_t *value, int timeout_ms) {
  (void)user;
  if (timeout_ms <= 0 && atomic_load(&g_pending) == 0) {
    return api_connected(NULL) ? 0 : -1;
  }
  pthread_mutex_lock(&g_lock);
  if (g_head == g_tail && timeout_ms > 0 && api_connected(NULL)) {
    struct timespec until;
    clock_gettime(CLOCK_REALTIME, &until);
    until.tv_nsec += (long)(timeout_ms % 1000) * 1000000L;
    until.tv_sec += timeout_ms / 1000 + until.tv_nsec / 1000000000L;
    until.tv_nsec %= 1000000000L;
    while (g_head == g_tail && api_connected(NULL)) {
      if (pthread_cond_timedwait(&g_inbox_cond, &g_lock, &until) == ETIMEDOUT) break;
    }
  }
  int r = 0;
  if (g_head != g_tail) {
    msg m = g_inbox[g_head++ % INBOX_CAP];
    atomic_fetch_sub(&g_pending, 1);
    *kind = m.kind;
    *value = m.value;
    r = 1;
  } else if (!api_connected(NULL)) {
    r = -1;
  }
  pthread_mutex_unlock(&g_lock);
  return r;
}

static const struct dena_link_api g_api = {
    DENA_LINK_API_VERSION, NULL, api_connected, api_role, api_send, api_recv};

const struct dena_link_api *dena_link_core_api(void) { return &g_api; }

#endif
