/**
 * Flutter Service Worker
 * Provides offline caching for PWA functionality
 * Cache strategies: network-first for API, cache-first for assets
 */

const CACHE_NAME = 'invoice-scanner-v1';
const STATIC_CACHE = 'invoice-scanner-static-v1';
const API_CACHE = 'invoice-scanner-api-v1';

// Assets to cache on install
const STATIC_ASSETS = [
  '/',
  '/index.html',
  '/main.dart.js',
  '/flutter_bootstrap.js',
  '/manifest.json',
  '/favicon.png',
  '/assets/fonts/MaterialIcons-Regular.otf',
];

// Install event - cache static assets
self.addEventListener('install', (event) => {
  console.log('[Service Worker] Installing...');
  
  event.waitUntil(
    caches.open(STATIC_CACHE)
      .then((cache) => {
        console.log('[Service Worker] Caching static assets');
        return cache.addAll(STATIC_ASSETS);
      })
      .then(() => {
        console.log('[Service Worker] Static assets cached');
        return self.skipWaiting();
      })
      .catch((error) => {
        console.error('[Service Worker] Cache failed:', error);
      })
  );
});

// Activate event - cleanup old caches
self.addEventListener('activate', (event) => {
  console.log('[Service Worker] Activating...');
  
  event.waitUntil(
    caches.keys()
      .then((cacheNames) => {
        return Promise.all(
          cacheNames.map((cacheName) => {
            if (cacheName !== STATIC_CACHE && cacheName !== API_CACHE) {
              console.log('[Service Worker] Deleting old cache:', cacheName);
              return caches.delete(cacheName);
            }
          })
        );
      })
      .then(() => {
        console.log('[Service Worker] Activated');
        return self.clients.claim();
      })
  );
});

// Fetch event - handle caching strategies
self.addEventListener('fetch', (event) => {
  const { request } = event;
  const url = new URL(request.url);
  
  // Skip non-GET requests
  if (request.method !== 'GET') {
    return;
  }
  
  // API requests - network-first with cache fallback
  if (url.pathname.startsWith('/api/')) {
    event.respondWith(networkFirstWithCache(request));
    return;
  }
  
  // Static assets - cache-first with network fallback
  event.respondWith(cacheFirstWithNetwork(request));
});

// Cache-first strategy for static assets
async function cacheFirstWithNetwork(request) {
  const cachedResponse = await caches.match(request);
  
  if (cachedResponse) {
    // Return cached version and update cache in background
    fetch(request)
      .then((networkResponse) => {
        if (networkResponse.ok) {
          caches.open(STATIC_CACHE).then((cache) => {
            cache.put(request, networkResponse.clone());
          });
        }
      })
      .catch(() => {}); // Ignore network errors for background update
    
    return cachedResponse;
  }
  
  // Not in cache, fetch from network
  try {
    const networkResponse = await fetch(request);
    
    if (networkResponse.ok) {
      const cache = await caches.open(STATIC_CACHE);
      cache.put(request, networkResponse.clone());
    }
    
    return networkResponse;
  } catch (error) {
    console.error('[Service Worker] Network fetch failed:', error);
    
    // Return offline fallback for HTML requests
    if (request.headers.get('accept').includes('text/html')) {
      return caches.match('/offline.html');
    }
    
    throw error;
  }
}

// Network-first strategy for API requests
async function networkFirstWithCache(request) {
  try {
    const networkResponse = await fetch(request);
    
    if (networkResponse.ok) {
      // Cache successful API responses
      const cache = await caches.open(API_CACHE);
      cache.put(request, networkResponse.clone());
      return networkResponse;
    }
    
    throw new Error('Network response not OK');
  } catch (error) {
    console.log('[Service Worker] Network failed, trying cache:', request.url);
    
    const cachedResponse = await caches.match(request);
    
    if (cachedResponse) {
      return cachedResponse;
    }
    
    // No cached response available
    console.error('[Service Worker] No cached response for:', request.url);
    throw error;
  }
}

// Background sync for offline submissions
self.addEventListener('sync', (event) => {
  if (event.tag === 'sync-scans') {
    console.log('[Service Worker] Background sync triggered');
    event.waitUntil(syncPendingScans());
  }
});

async function syncPendingScans() {
  // This would sync pending scans when connection is restored
  // Implementation depends on the app's offline storage mechanism
  console.log('[Service Worker] Syncing pending scans...');
}

// Push notification handling
self.addEventListener('push', (event) => {
  console.log('[Service Worker] Push received:', event);
  
  const options = {
    body: event.data?.text() || 'New notification',
    icon: '/icons/icon-192x192.png',
    badge: '/icons/badge-72x72.png',
    tag: 'scan-complete',
    requireInteraction: true,
    actions: [
      {
        action: 'view',
        title: 'View'
      },
      {
        action: 'close',
        title: 'Close'
      }
    ]
  };
  
  event.waitUntil(
    self.registration.showNotification('Invoice Scanner', options)
  );
});

// Notification click handling
self.addEventListener('notificationclick', (event) => {
  console.log('[Service Worker] Notification click:', event);
  
  event.notification.close();
  
  if (event.action === 'view') {
    event.waitUntil(
      clients.openWindow('/history')
    );
  }
});

// Message handling from main app
self.addEventListener('message', (event) => {
  console.log('[Service Worker] Message received:', event.data);
  
  if (event.data === 'skipWaiting') {
    self.skipWaiting();
  }
});

// Periodic background sync (for checking updates)
self.addEventListener('periodicsync', (event) => {
  if (event.tag === 'check-updates') {
    console.log('[Service Worker] Periodic sync: checking updates');
    event.waitUntil(checkForUpdates());
  }
});

async function checkForUpdates() {
  // Check for app updates
  // This could trigger a notification or update the cache
  console.log('[Service Worker] Checking for updates...');
}
