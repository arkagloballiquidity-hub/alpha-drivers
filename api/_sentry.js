import * as Sentry from '@sentry/node';

let _initialized = false;

export function initSentry() {
  if (_initialized || !process.env.SENTRY_DSN) return;
  Sentry.init({
    dsn: process.env.SENTRY_DSN,
    environment: process.env.VERCEL_ENV || 'development',
    tracesSampleRate: 0.1,
  });
  _initialized = true;
}

export function captureException(err, context = {}) {
  initSentry();
  Sentry.withScope(scope => {
    Object.entries(context).forEach(([k, v]) => scope.setExtra(k, v));
    Sentry.captureException(err);
  });
}
