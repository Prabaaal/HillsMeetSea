(function () {
  function base64ToUint8Array(base64String) {
    const padding = '='.repeat((4 - (base64String.length % 4)) % 4);
    const base64 = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/');
    const rawData = window.atob(base64);
    const output = new Uint8Array(rawData.length);

    for (let i = 0; i < rawData.length; i += 1) {
      output[i] = rawData.charCodeAt(i);
    }

    return output;
  }

  async function getPushRegistration() {
    return navigator.serviceWorker.register('/push_worker.js', { scope: '/push/' });
  }

  window.HMSPush = {
    isSupported() {
      return 'serviceWorker' in navigator && 'PushManager' in window && 'Notification' in window;
    },

    permission() {
      if (!this.isSupported()) {
        return 'unsupported';
      }
      return Notification.permission;
    },

    async requestPermission() {
      if (!this.isSupported()) {
        return 'unsupported';
      }
      return Notification.requestPermission();
    },

    async ensureSubscription(vapidKey) {
      if (!this.isSupported() || !vapidKey) {
        return null;
      }

      const registration = await getPushRegistration();
      let subscription = await registration.pushManager.getSubscription();

      if (!subscription) {
        subscription = await registration.pushManager.subscribe({
          userVisibleOnly: true,
          applicationServerKey: base64ToUint8Array(vapidKey),
        });
      }

      return JSON.stringify(subscription.toJSON());
    },

    async unsubscribe() {
      if (!this.isSupported()) {
        return '';
      }

      const registration = await getPushRegistration();
      const subscription = await registration.pushManager.getSubscription();
      if (!subscription) {
        return '';
      }

      const endpoint = subscription.endpoint;
      await subscription.unsubscribe();
      return endpoint;
    },
  };
}());
