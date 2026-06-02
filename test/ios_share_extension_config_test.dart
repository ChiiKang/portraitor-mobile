import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('iOS share extension configuration', () {
    test('registers Portraitor as a WhatsApp chat export share target', () {
      final runnerInfo = File('ios/Runner/Info.plist').readAsStringSync();
      final podfile = File('ios/Podfile').readAsStringSync();
      final project = File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
      final shareInfo = File('ios/Share Extension/Info.plist');
      final shareController = File('ios/Share Extension/ShareViewController.swift');
      final shareStoryboard = File('ios/Share Extension/Base.lproj/MainInterface.storyboard');
      final runnerEntitlements = File('ios/Runner/Runner.entitlements');
      final shareEntitlements = File('ios/Share Extension/Share Extension.entitlements');

      expect(shareInfo.existsSync(), isTrue);
      expect(shareController.existsSync(), isTrue);
      expect(shareStoryboard.existsSync(), isTrue);
      expect(runnerEntitlements.existsSync(), isTrue);
      expect(shareEntitlements.existsSync(), isTrue);

      final shareInfoText = shareInfo.readAsStringSync();
      final shareControllerText = shareController.readAsStringSync();
      final runnerEntitlementsText = runnerEntitlements.readAsStringSync();
      final shareEntitlementsText = shareEntitlements.readAsStringSync();

      expect(runnerInfo, contains('<key>AppGroupId</key>'));
      expect(runnerInfo, contains('group.ai.portraitor.portraitorMobile'));
      expect(runnerInfo, contains(r'ShareMedia-$(PRODUCT_BUNDLE_IDENTIFIER)'));

      expect(shareInfoText, contains('<key>AppGroupId</key>'));
      expect(shareInfoText, contains(r'$(CUSTOM_GROUP_ID)'));
      expect(shareInfoText, contains('<key>CFBundleVersion</key>'));
      expect(shareInfoText, contains('<string>1</string>'));
      expect(shareInfoText, contains('<key>CFBundleShortVersionString</key>'));
      expect(shareInfoText, contains('<string>1.0</string>'));
      expect(shareInfoText, contains('NSExtensionActivationSupportsFileWithMaxCount'));
      expect(shareInfoText, contains('NSExtensionActivationSupportsText'));
      expect(shareInfoText, contains('com.apple.share-services'));

      expect(shareControllerText, isNot(contains('import receive_sharing_intent')));
      expect(shareControllerText, isNot(contains('RSIShareViewController')));
      expect(shareControllerText, contains('ShareKey'));
      expect(shareControllerText, contains('ShareMedia-'));

      expect(runnerEntitlementsText, contains('com.apple.security.application-groups'));
      expect(runnerEntitlementsText, contains('group.ai.portraitor.portraitorMobile'));
      expect(shareEntitlementsText, contains('com.apple.security.application-groups'));
      expect(shareEntitlementsText, contains('group.ai.portraitor.portraitorMobile'));

      expect(podfile, isNot(contains("target 'Share Extension' do")));

      expect(project, contains('Share Extension.appex'));
      expect(project, contains('com.apple.product-type.app-extension'));
      expect(project, contains('CODE_SIGN_ENTITLEMENTS = "Share Extension/Share Extension.entitlements"'));
      expect(project, contains('INFOPLIST_FILE = "Share Extension/Info.plist"'));
      expect(project, contains('PRODUCT_BUNDLE_IDENTIFIER = ai.portraitor.portraitorMobile.ShareExtension'));
      expect(project, contains('CUSTOM_GROUP_ID = group.ai.portraitor.portraitorMobile'));
      expect(project, contains('CURRENT_PROJECT_VERSION = 1'));
      expect(project, contains('MARKETING_VERSION = 1.0'));
      expect(project, contains('Sign Native Assets Frameworks'));
      expect(project, contains('objective_c.framework'));
    });
  });
}
