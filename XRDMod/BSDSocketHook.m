#import <Foundation/Foundation.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <netdb.h>

#pragma mark - DYLD Interpose

#define DYLD_INTERPOSE(_replacement, _replacee) \
    __attribute__((used)) static struct { \
        const void* replacement; \
        const void* replacee; \
    } _interpose_##_replacee \
    __attribute__((section("__DATA,__interpose"))) = { \
        (const void*)(unsigned long)&_replacement, \
        (const void*)(unsigned long)&_replacee \
    };

#pragma mark - State

static NSMutableArray<NSString *> *g_conns;
static NSMutableArray<NSString *> *g_dns;
static NSMutableDictionary<NSString *, NSString *> *g_dnsMap;
static BOOL g_ready = NO;

static NSString * const kNotif = @"XRDBSDConnection";
static NSString * const kConnsKey = @"XRD_bsdConns";
static NSString * const kDNSKey = @"XRD_bsdDNS";

__attribute__((constructor))
static void bsd_hook_init(void) {
    g_conns = [NSMutableArray new];
    g_dns = [NSMutableArray new];
    g_dnsMap = [NSMutableDictionary new];
    g_ready = YES;
}

#pragma mark - connect() hook

int xrd_connect(int sockfd, const struct sockaddr *addr, socklen_t addrlen) {
    if (g_ready && addr) {
        char ip[INET6_ADDRSTRLEN] = {0};
        int port = 0;

        if (addr->sa_family == AF_INET) {
            struct sockaddr_in *sin = (struct sockaddr_in *)addr;
            inet_ntop(AF_INET, &sin->sin_addr, ip, sizeof(ip));
            port = ntohs(sin->sin_port);
        } else if (addr->sa_family == AF_INET6) {
            struct sockaddr_in6 *sin6 = (struct sockaddr_in6 *)addr;
            inet_ntop(AF_INET6, &sin6->sin6_addr, ip, sizeof(ip));
            port = ntohs(sin6->sin6_port);
        }

        if (port > 0) {
            NSString *ipStr = @(ip);
            NSString *hostname = nil;
            @synchronized(g_dnsMap) {
                hostname = [g_dnsMap[ipStr] copy];
            }

            NSString *entry;
            if (hostname) {
                entry = [NSString stringWithFormat:@"%@:%d (%@)", hostname, port, ipStr];
            } else {
                entry = [NSString stringWithFormat:@"%@:%d", ipStr, port];
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                if (g_conns.count >= 200) [g_conns removeObjectAtIndex:0];
                [g_conns addObject:entry];

                BOOL isGame = NO;
                if (hostname) {
                    NSString *h = [hostname lowercaseString];
                    isGame = [h containsString:@"agar"] ||
                             [h containsString:@"arena"] ||
                             [h containsString:@"miniclip"] ||
                             [h containsString:@"live-"];
                }

                if (isGame) {
                    NSString *wsURL = [NSString stringWithFormat:@"wss://%@:%d", hostname, port];
                    [[NSUserDefaults standardUserDefaults] setObject:wsURL forKey:@"XRD_bsdServer"];
                    [[NSNotificationCenter defaultCenter]
                        postNotificationName:kNotif object:nil
                        userInfo:@{@"url": wsURL, @"ip": ipStr,
                                   @"port": @(port), @"host": hostname}];
                }

                if (g_conns.count % 5 == 0) {
                    [[NSUserDefaults standardUserDefaults] setObject:[g_conns copy] forKey:kConnsKey];
                }
            });
        }
    }
    return connect(sockfd, addr, addrlen);
}

#pragma mark - getaddrinfo() hook

int xrd_getaddrinfo(const char *node, const char *service,
                     const struct addrinfo *hints, struct addrinfo **res) {
    int ret = getaddrinfo(node, service, hints, res);

    if (g_ready && ret == 0 && node && res && *res) {
        NSString *host = @(node);
        struct addrinfo *rp = *res;
        while (rp) {
            if (rp->ai_addr) {
                char ip[INET6_ADDRSTRLEN] = {0};
                if (rp->ai_family == AF_INET) {
                    struct sockaddr_in *sin = (struct sockaddr_in *)rp->ai_addr;
                    inet_ntop(AF_INET, &sin->sin_addr, ip, sizeof(ip));
                } else if (rp->ai_family == AF_INET6) {
                    struct sockaddr_in6 *sin6 = (struct sockaddr_in6 *)rp->ai_addr;
                    inet_ntop(AF_INET6, &sin6->sin6_addr, ip, sizeof(ip));
                }

                if (ip[0] != '\0') {
                    NSString *ipStr = @(ip);
                    @synchronized(g_dnsMap) {
                        g_dnsMap[ipStr] = host;
                    }

                    NSString *dnsEntry = [NSString stringWithFormat:@"%@ -> %@", host, ipStr];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (g_dns.count >= 200) [g_dns removeObjectAtIndex:0];
                        [g_dns addObject:dnsEntry];

                        if (g_dns.count % 5 == 0) {
                            [[NSUserDefaults standardUserDefaults] setObject:[g_dns copy] forKey:kDNSKey];
                        }
                    });
                    break;
                }
            }
            rp = rp->ai_next;
        }
    }

    return ret;
}

DYLD_INTERPOSE(xrd_connect, connect)
DYLD_INTERPOSE(xrd_getaddrinfo, getaddrinfo)

#pragma mark - ObjC interface (called from Swift via runtime)

@interface XRDBSDHook : NSObject
+ (NSArray<NSString *> *)capturedConnections;
+ (NSArray<NSString *> *)capturedDNS;
+ (void)syncToDefaults;
@end

@implementation XRDBSDHook

+ (NSArray<NSString *> *)capturedConnections {
    return [g_conns copy] ?: @[];
}

+ (NSArray<NSString *> *)capturedDNS {
    return [g_dns copy] ?: @[];
}

+ (void)syncToDefaults {
    [[NSUserDefaults standardUserDefaults] setObject:[g_conns copy] forKey:kConnsKey];
    [[NSUserDefaults standardUserDefaults] setObject:[g_dns copy] forKey:kDNSKey];
}

@end
