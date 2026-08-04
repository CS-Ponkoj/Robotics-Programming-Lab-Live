bool isAuthenticatedAppEntry(Uri location) {
  return location.path == '/app' || location.fragment == '/app';
}
