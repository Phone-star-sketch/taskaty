# taskaty

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Setup Instructions

### Environment Configuration

1. **For Mobile/Desktop**: Copy `.env.template` to `assets/.env` and fill in your values
2. **For Web**: Copy `web/config.template.js` to `web/config.js` and fill in your values

### Important Security Notes

- Never commit actual API keys or service account credentials
- The `web/config.js` file is gitignored for security
- Firebase service account keys should only be used server-side

## Build Commands

```bash
# Mobile build
flutter build apk

# Web build  
flutter build web
```

Make sure to create your config.js file before building for web.
