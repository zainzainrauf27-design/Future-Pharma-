(() => {
  const DB_NAME = 'future-pharma-offline-v1';
  const STORE = 'records';
  let opened;
  function db() {
    if (!('indexedDB' in window)) return Promise.reject(new Error('This browser does not support local offline storage.'));
    if (!opened) opened = new Promise((resolve, reject) => {
      const request = indexedDB.open(DB_NAME, 1);
      request.onupgradeneeded = () => request.result.createObjectStore(STORE, { keyPath: 'key' });
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
    return opened;
  }
  async function transaction(mode, action) {
    const database = await db();
    return new Promise((resolve, reject) => {
      const tx = database.transaction(STORE, mode), store = tx.objectStore(STORE);
      let result;
      try { result = action(store); } catch (error) { reject(error); return; }
      tx.oncomplete = () => resolve(result?.result);
      tx.onerror = () => reject(tx.error);
      tx.onabort = () => reject(tx.error || new Error('Offline storage transaction failed.'));
    });
  }
  const key = (userId, name) => `${userId}:${name}`;
  async function get(userId, name) {
    const database = await db();
    return new Promise((resolve, reject) => {
      const request = database.transaction(STORE, 'readonly').objectStore(STORE).get(key(userId, name));
      request.onsuccess = () => resolve(request.result?.value ?? null);
      request.onerror = () => reject(request.error);
    });
  }
  async function set(userId, name, value) {
    const database = await db();
    return new Promise((resolve, reject) => {
      const tx = database.transaction(STORE, 'readwrite');
      tx.objectStore(STORE).put({ key: key(userId, name), value });
      tx.oncomplete = () => resolve(value);
      tx.onerror = () => reject(tx.error);
    });
  }
  async function list(userId, prefix) {
    const database = await db();
    return new Promise((resolve, reject) => {
      const request = database.transaction(STORE, 'readonly').objectStore(STORE).getAll();
      request.onsuccess = () => resolve(request.result.filter(x => x.key.startsWith(`${userId}:${prefix}`)).map(x => x.value));
      request.onerror = () => reject(request.error);
    });
  }
  async function nextOrderId(userId) {
    const database = await db(), counterKey = key(userId, 'local-order-counter');
    const next = await new Promise((resolve, reject) => {
      const tx = database.transaction(STORE, 'readwrite'), store = tx.objectStore(STORE), request = store.get(counterKey);
      let value = 1;
      request.onsuccess = () => { value = Number(request.result?.value || 0) + 1; store.put({ key: counterKey, value }); };
      request.onerror = () => reject(request.error);
      tx.oncomplete = () => resolve(value);
      tx.onerror = () => reject(tx.error);
    });
    return `LOCAL-ORD-${String(next).padStart(6, '0')}`;
  }
  window.FPOffline = { get, set, list, nextOrderId };
})();
