const bool selfServicePasswordResetEnabled = bool.fromEnvironment(
  'ENABLE_SELF_SERVICE_PASSWORD_RESET',
  defaultValue: false,
);

const bool instructorEmailToolsEnabled = bool.fromEnvironment(
  'ENABLE_INSTRUCTOR_EMAIL_TOOLS',
  defaultValue: false,
);
