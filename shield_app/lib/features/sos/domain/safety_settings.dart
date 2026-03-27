class SafetySettings {
  const SafetySettings({
    required this.primaryEmergencyNumber,
    required this.womenHelplineNumber,
    required this.disguiseModeEnabled,
    required this.autoCallPrimaryContact,
    required this.sendWomenHelplinePrompt,
    required this.checkInMinutes,
  });

  final String primaryEmergencyNumber;
  final String womenHelplineNumber;
  final bool disguiseModeEnabled;
  final bool autoCallPrimaryContact;
  final bool sendWomenHelplinePrompt;
  final int checkInMinutes;

  factory SafetySettings.defaults() {
    return const SafetySettings(
      primaryEmergencyNumber: '112',
      womenHelplineNumber: '181',
      disguiseModeEnabled: false,
      autoCallPrimaryContact: true,
      sendWomenHelplinePrompt: true,
      checkInMinutes: 30,
    );
  }

  SafetySettings copyWith({
    String? primaryEmergencyNumber,
    String? womenHelplineNumber,
    bool? disguiseModeEnabled,
    bool? autoCallPrimaryContact,
    bool? sendWomenHelplinePrompt,
    int? checkInMinutes,
  }) {
    return SafetySettings(
      primaryEmergencyNumber:
          primaryEmergencyNumber ?? this.primaryEmergencyNumber,
      womenHelplineNumber: womenHelplineNumber ?? this.womenHelplineNumber,
      disguiseModeEnabled: disguiseModeEnabled ?? this.disguiseModeEnabled,
      autoCallPrimaryContact:
          autoCallPrimaryContact ?? this.autoCallPrimaryContact,
      sendWomenHelplinePrompt:
          sendWomenHelplinePrompt ?? this.sendWomenHelplinePrompt,
      checkInMinutes: checkInMinutes ?? this.checkInMinutes,
    );
  }

  Map<String, String> toStorage() {
    return {
      'primaryEmergencyNumber': primaryEmergencyNumber,
      'womenHelplineNumber': womenHelplineNumber,
      'disguiseModeEnabled': disguiseModeEnabled.toString(),
      'autoCallPrimaryContact': autoCallPrimaryContact.toString(),
      'sendWomenHelplinePrompt': sendWomenHelplinePrompt.toString(),
      'checkInMinutes': checkInMinutes.toString(),
    };
  }

  factory SafetySettings.fromStorage(Map<String, String> values) {
    final defaults = SafetySettings.defaults();
    return SafetySettings(
      primaryEmergencyNumber:
          values['primaryEmergencyNumber'] ?? defaults.primaryEmergencyNumber,
      womenHelplineNumber:
          values['womenHelplineNumber'] ?? defaults.womenHelplineNumber,
      disguiseModeEnabled: values['disguiseModeEnabled'] == null
          ? defaults.disguiseModeEnabled
          : values['disguiseModeEnabled'] == 'true',
      autoCallPrimaryContact:
          values['autoCallPrimaryContact'] == null
              ? defaults.autoCallPrimaryContact
              : values['autoCallPrimaryContact'] == 'true',
      sendWomenHelplinePrompt:
          values['sendWomenHelplinePrompt'] == null
              ? defaults.sendWomenHelplinePrompt
              : values['sendWomenHelplinePrompt'] == 'true',
      checkInMinutes:
          int.tryParse(values['checkInMinutes'] ?? '') ?? defaults.checkInMinutes,
    );
  }
}
