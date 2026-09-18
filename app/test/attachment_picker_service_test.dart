import 'package:app/services/attachment_picker_service.dart';
import 'package:app/utils/runtime_platform.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('imageVideoUsesDesktopFilePicker follows desktop or ohos photo gate', () {
    expect(
      AttachmentPickerService.imageVideoUsesDesktopFilePicker,
      RuntimePlatform.isDesktop || !OhosCapabilities.photoManagerPicker,
    );
  });
}
