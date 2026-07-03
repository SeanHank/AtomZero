#!/usr/bin/env python3
"""
Generate export_presets.cfg for AtomZero with presets for all target platforms.

Scans the core/ directory and icon.svg to build the export_files list, then
generates presets for macOS, Linux, Windows, Android, and iOS.

The macOS preset mirrors the hand-tuned configuration already in the repo
(universal binary, bundle identifier, version, etc.). The remaining presets
are generated with platform-appropriate defaults.

Usage:
    python3 tools/ci/generate_export_presets.py [--version VERSION] [--output PATH]

    --version   Override the game version (default: read from project.godot)
    --output    Output path (default: export_presets.cfg in project root)
"""

import argparse
import os
import sys
from pathlib import Path


# File extensions that Godot can export as resources
EXPORTABLE_EXTENSIONS = {
    ".gd", ".tscn", ".scn", ".tres", ".res", ".json", ".svg",
    ".png", ".jpg", ".jpeg", ".webp", ".ctex", ".dds",
    ".glb", ".gltf", ".obj",
    ".wav", ".ogg", ".mp3",
    ".ttf", ".otf", ".woff",
    ".import",
}


def find_project_root() -> Path:
    """Find the project root by looking for project.godot."""
    current = Path(__file__).resolve().parent
    while current != current.parent:
        if (current / "project.godot").exists():
            return current
        current = current.parent
    raise RuntimeError("Could not find project.godot - is this run from an AtomZero project?")


def get_version_from_project(project_root: Path) -> str:
    """Extract config/version from project.godot."""
    godot_file = project_root / "project.godot"
    with open(godot_file, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line.startswith("config/version="):
                return line.split("=", 1)[1].strip().strip('"')
    return "0.0.0"


def scan_export_files(project_root: Path) -> list:
    """
    Scan core/ directory and icon.svg to build the list of exportable files.

    Returns a list of res:// paths sorted alphabetically.
    """
    files = []

    core_dir = project_root / "core"
    if not core_dir.is_dir():
        raise RuntimeError(f"core/ directory not found at {core_dir}")

    for path in sorted(core_dir.rglob("*")):
        if path.is_file():
            rel = path.relative_to(project_root)
            ext = path.suffix.lower()
            if ext in EXPORTABLE_EXTENSIONS:
                files.append(f"res://{rel.as_posix()}")

    icon = project_root / "icon.svg"
    if icon.exists():
        res_path = "res://icon.svg"
        if res_path not in files:
            files.append(res_path)

    files.sort()
    return files


def format_packed_string_array(items):
    """Format a list of strings as a Godot PackedStringArray literal."""
    escaped = []
    for item in items:
        escaped.append(f'"{item}"')
    return "PackedStringArray(" + ", ".join(escaped) + ")"


def generate_macos_preset(version: str, export_files: list) -> str:
    """Generate the macOS preset, mirroring the existing hand-tuned config."""
    files_str = format_packed_string_array(export_files)
    return f"""
[preset.0]

name="macOS"
platform="macOS"
runnable=true
dedicated_server=false
custom_features=""
export_filter="resources"
export_files={files_str}
include_filter=""
exclude_filter=""
export_path="dist/AtomZero.app"
patches=PackedStringArray()
patch_delta_encoding=false
patch_delta_compression_level_zstd=19
patch_delta_min_reduction=0.1
patch_delta_include_filters="*"
patch_delta_exclude_filters=""
encryption_include_filters=""
encryption_exclude_filters=""
seed=0
encrypt_pck=false
encrypt_directory=false
script_export_mode=2

[preset.0.options]

export/distribution_type=1
binary_format/architecture="universal"
custom_template/debug=""
custom_template/release=""
debug/export_console_wrapper=2
application/liquid_glass_icon=""
application/icon=""
application/icon_interpolation=4
application/bundle_identifier="com.atom.zero"
application/signature=""
application/app_category="Games"
application/short_version="{version}"
application/version="{version}"
application/copyright="© 2026 AtomLife Studio. All rights reserved. "
application/copyright_localized={{}}
application/min_macos_version_x86_64="10.12"
application/min_macos_version_arm64="11.00"
application/export_angle=0
display/high_res=true
shader_baker/enabled=false
application/additional_plist_content=""
xcode/platform_build="14C18"
xcode/sdk_version="13.1"
xcode/sdk_build="22C55"
xcode/sdk_name="macosx13.1"
xcode/xcode_version="1420"
xcode/xcode_build="14C18"
codesign/codesign=3
codesign/installer_identity=""
codesign/apple_team_id=""
codesign/identity=""
codesign/entitlements/custom_file=""
codesign/entitlements/allow_jit_code_execution=false
codesign/entitlements/allow_unsigned_executable_memory=false
codesign/entitlements/allow_dyld_environment_variables=false
codesign/entitlements/disable_library_validation=false
codesign/entitlements/audio_input=false
codesign/entitlements/camera=false
codesign/entitlements/location=false
codesign/entitlements/address_book=false
codesign/entitlements/calendars=false
codesign/entitlements/photos_library=false
codesign/entitlements/apple_events=false
codesign/entitlements/debugging=false
codesign/entitlements/app_sandbox/enabled=false
codesign/entitlements/app_sandbox/network_server=false
codesign/entitlements/app_sandbox/network_client=false
codesign/entitlements/app_sandbox/device_usb=false
codesign/entitlements/app_sandbox/device_bluetooth=false
codesign/entitlements/app_sandbox/files_downloads=0
codesign/entitlements/app_sandbox/files_pictures=0
codesign/entitlements/app_sandbox/files_music=0
codesign/entitlements/app_sandbox/files_movies=0
codesign/entitlements/app_sandbox/files_user_selected=0
codesign/entitlements/app_sandbox/helper_executables=[]
codesign/entitlements/additional=""
codesign/custom_options=PackedStringArray()
notarization/notarization=0
privacy/microphone_usage_description=""
privacy/microphone_usage_description_localized={{}}
privacy/camera_usage_description=""
privacy/camera_usage_description_localized={{}}
privacy/location_usage_description=""
privacy/location_usage_description_localized={{}}
privacy/address_book_usage_description=""
privacy/address_book_usage_description_localized={{}}
privacy/calendar_usage_description=""
privacy/calendar_usage_description_localized={{}}
privacy/photos_library_usage_description=""
privacy/photos_library_usage_description_localized={{}}
privacy/desktop_folder_usage_description=""
privacy/desktop_folder_usage_description_localized={{}}
privacy/documents_folder_usage_description=""
privacy/documents_folder_usage_description_localized={{}}
privacy/downloads_folder_usage_description=""
privacy/downloads_folder_usage_description_localized={{}}
privacy/network_volumes_usage_description=""
privacy/network_volumes_usage_description_localized={{}}
privacy/removable_volumes_usage_description=""
privacy/removable_volumes_usage_description_localized={{}}
privacy/tracking_enabled=false
privacy/tracking_domains=PackedStringArray()
privacy/collected_data/name/collected=false
privacy/collected_data/name/linked_to_user=false
privacy/collected_data/name/used_for_tracking=false
privacy/collected_data/name/collection_purposes=0
privacy/collected_data/email_address/collected=false
privacy/collected_data/email_address/linked_to_user=false
privacy/collected_data/email_address/used_for_tracking=false
privacy/collected_data/email_address/collection_purposes=0
privacy/collected_data/phone_number/collected=false
privacy/collected_data/phone_number/linked_to_user=false
privacy/collected_data/phone_number/used_for_tracking=false
privacy/collected_data/phone_number/collection_purposes=0
privacy/collected_data/physical_address/collected=false
privacy/collected_data/physical_address/linked_to_user=false
privacy/collected_data/physical_address/used_for_tracking=false
privacy/collected_data/physical_address/collection_purposes=0
privacy/collected_data/other_contact_info/collected=false
privacy/collected_data/other_contact_info/linked_to_user=false
privacy/collected_data/other_contact_info/used_for_tracking=false
privacy/collected_data/other_contact_info/collection_purposes=0
privacy/collected_data/health/collected=false
privacy/collected_data/health/linked_to_user=false
privacy/collected_data/health/used_for_tracking=false
privacy/collected_data/health/collection_purposes=0
privacy/collected_data/fitness/collected=false
privacy/collected_data/fitness/linked_to_user=false
privacy/collected_data/fitness/used_for_tracking=false
privacy/collected_data/fitness/collection_purposes=0
privacy/collected_data/payment_info/collected=false
privacy/collected_data/payment_info/linked_to_user=false
privacy/collected_data/payment_info/used_for_tracking=false
privacy/collected_data/payment_info/collection_purposes=0
privacy/collected_data/credit_info/collected=false
privacy/collected_data/credit_info/linked_to_user=false
privacy/collected_data/credit_info/used_for_tracking=false
privacy/collected_data/credit_info/collection_purposes=0
privacy/collected_data/other_financial_info/collected=false
privacy/collected_data/other_financial_info/linked_to_user=false
privacy/collected_data/other_financial_info/used_for_tracking=false
privacy/collected_data/other_financial_info/collection_purposes=0
privacy/collected_data/precise_location/collected=false
privacy/collected_data/precise_location/linked_to_user=false
privacy/collected_data/precise_location/used_for_tracking=false
privacy/collected_data/precise_location/collection_purposes=0
privacy/collected_data/coarse_location/collected=false
privacy/collected_data/coarse_location/linked_to_user=false
privacy/collected_data/coarse_location/used_for_tracking=false
privacy/collected_data/coarse_location/collection_purposes=0
privacy/collected_data/sensitive_info/collected=false
privacy/collected_data/sensitive_info/linked_to_user=false
privacy/collected_data/sensitive_info/used_for_tracking=false
privacy/collected_data/sensitive_info/collection_purposes=0
privacy/collected_data/contacts/collected=false
privacy/collected_data/contacts/linked_to_user=false
privacy/collected_data/contacts/used_for_tracking=false
privacy/collected_data/contacts/collection_purposes=0
privacy/collected_data/emails_or_text_messages/collected=false
privacy/collected_data/emails_or_text_messages/linked_to_user=false
privacy/collected_data/emails_or_text_messages/used_for_tracking=false
privacy/collected_data/emails_or_text_messages/collection_purposes=0
privacy/collected_data/photos_or_videos/collected=false
privacy/collected_data/photos_or_videos/linked_to_user=false
privacy/collected_data/photos_or_videos/used_for_tracking=false
privacy/collected_data/photos_or_videos/collection_purposes=0
privacy/collected_data/audio_data/collected=false
privacy/collected_data/audio_data/linked_to_user=false
privacy/collected_data/audio_data/used_for_tracking=false
privacy/collected_data/audio_data/collection_purposes=0
privacy/collected_data/gameplay_content/collected=false
privacy/collected_data/gameplay_content/linked_to_user=false
privacy/collected_data/gameplay_content/used_for_tracking=false
privacy/collected_data/gameplay_content/collection_purposes=0
privacy/collected_data/customer_support/collected=false
privacy/collected_data/customer_support/linked_to_user=false
privacy/collected_data/customer_support/used_for_tracking=false
privacy/collected_data/customer_support/collection_purposes=0
privacy/collected_data/other_user_content/collected=false
privacy/collected_data/other_user_content/linked_to_user=false
privacy/collected_data/other_user_content/used_for_tracking=false
privacy/collected_data/other_user_content/collection_purposes=0
privacy/collected_data/browsing_history/collected=false
privacy/collected_data/browsing_history/linked_to_user=false
privacy/collected_data/browsing_history/used_for_tracking=false
privacy/collected_data/browsing_history/collection_purposes=0
privacy/collected_data/search_history/collected=false
privacy/collected_data/search_history/linked_to_user=false
privacy/collected_data/search_history/used_for_tracking=false
privacy/collected_data/search_history/collection_purposes=0
privacy/collected_data/user_id/collected=false
privacy/collected_data/user_id/linked_to_user=false
privacy/collected_data/user_id/used_for_tracking=false
privacy/collected_data/user_id/collection_purposes=0
privacy/collected_data/device_id/collected=false
privacy/collected_data/device_id/linked_to_user=false
privacy/collected_data/device_id/used_for_tracking=false
privacy/collected_data/device_id/collection_purposes=0
privacy/collected_data/purchase_history/collected=false
privacy/collected_data/purchase_history/linked_to_user=false
privacy/collected_data/purchase_history/used_for_tracking=false
privacy/collected_data/purchase_history/collection_purposes=0
privacy/collected_data/product_interaction/collected=false
privacy/collected_data/product_interaction/linked_to_user=false
privacy/collected_data/product_interaction/used_for_tracking=false
privacy/collected_data/product_interaction/collection_purposes=0
privacy/collected_data/advertising_data/collected=false
privacy/collected_data/advertising_data/linked_to_user=false
privacy/collected_data/advertising_data/used_for_tracking=false
privacy/collected_data/advertising_data/collection_purposes=0
privacy/collected_data/other_usage_data/collected=false
privacy/collected_data/other_usage_data/linked_to_user=false
privacy/collected_data/other_usage_data/used_for_tracking=false
privacy/collected_data/other_usage_data/collection_purposes=0
privacy/collected_data/crash_data/collected=false
privacy/collected_data/crash_data/linked_to_user=false
privacy/collected_data/crash_data/used_for_tracking=false
privacy/collected_data/crash_data/collection_purposes=0
privacy/collected_data/performance_data/collected=false
privacy/collected_data/performance_data/linked_to_user=false
privacy/collected_data/performance_data/used_for_tracking=false
privacy/collected_data/performance_data/collection_purposes=0
privacy/collected_data/other_diagnostic_data/collected=false
privacy/collected_data/other_diagnostic_data/linked_to_user=false
privacy/collected_data/other_diagnostic_data/used_for_tracking=false
privacy/collected_data/other_diagnostic_data/collection_purposes=0
privacy/collected_data/environment_scanning/collected=false
privacy/collected_data/environment_scanning/linked_to_user=false
privacy/collected_data/environment_scanning/used_for_tracking=false
privacy/collected_data/environment_scanning/collection_purposes=0
privacy/collected_data/hands/collected=false
privacy/collected_data/hands/linked_to_user=false
privacy/collected_data/hands/used_for_tracking=false
privacy/collected_data/hands/collection_purposes=0
privacy/collected_data/head/collected=false
privacy/collected_data/head/linked_to_user=false
privacy/collected_data/head/used_for_tracking=false
privacy/collected_data/head/collection_purposes=0
privacy/collected_data/other_data_types/collected=false
privacy/collected_data/other_data_types/linked_to_user=false
privacy/collected_data/other_data_types/used_for_tracking=false
privacy/collected_data/other_data_types/collection_purposes=0
ssh_remote_deploy/enabled=false
ssh_remote_deploy/host="user@host_ip"
ssh_remote_deploy/port="22"
ssh_remote_deploy/extra_args_ssh=""
ssh_remote_deploy/extra_args_scp=""
ssh_remote_deploy/run_script="#!/usr/bin/env bash\\nunzip -o -q \\"{{temp_dir}}/{{archive_name}}\\" -d \\"{{temp_dir}}\\"\\nopen \\"{{temp_dir}}/{{exe_name}}.app\\" --args {{cmd_args}}"
ssh_remote_deploy/cleanup_script="#!/usr/bin/env bash\\npkill -x -f \\"{{temp_dir}}/{{exe_name}}.app/Contents/MacOS/{{exe_name}} {{cmd_args}}\\"\\nrm -rf \\"{{temp_dir}}\\""
"""


def generate_linux_preset(version: str, export_files: list) -> str:
    """Generate the Linux desktop preset."""
    files_str = format_packed_string_array(export_files)
    return f"""
[preset.1]

name="Linux"
platform="Linux"
runnable=true
dedicated_server=false
custom_features=""
export_filter="resources"
export_files={files_str}
include_filter=""
exclude_filter=""
export_path="dist/AtomZero.x86_64"
patches=PackedStringArray()
patch_delta_encoding=false
patch_delta_compression_level_zstd=19
patch_delta_min_reduction=0.1
patch_delta_include_filters="*"
patch_delta_exclude_filters=""
encryption_include_filters=""
encryption_exclude_filters=""
seed=0
encrypt_pck=false
encrypt_directory=false
script_export_mode=2

[preset.1.options]

custom_template/debug=""
custom_template/release=""
debug/export_console_wrapper=1
binary_format/architecture="x86_64"
ssh_remote_deploy/enabled=false
ssh_remote_deploy/host="user@host_ip"
ssh_remote_deploy/port="22"
ssh_remote_deploy/extra_args_ssh=""
ssh_remote_deploy/extra_args_scp=""
ssh_remote_deploy/run_script="#!/usr/bin/env bash\\nexport DISPLAY=:0\\nunzip -o -q \\"{{temp_dir}}/{{archive_name}}\\" -d \\"{{temp_dir}}\\"\\n\\"{{temp_dir}}/{{exe_name}}\\" {{cmd_args}}"
ssh_remote_deploy/cleanup_script="#!/usr/bin/env bash\\nkillall -9 -e \\"{{temp_dir}}/{{exe_name}}\\" || true\\nrm -rf \\"{{temp_dir}}\\""
texture_format/s3tc=true
texture_format/etc2=false
"""


def generate_windows_preset(version: str, export_files: list) -> str:
    """Generate the Windows desktop preset (targeting Windows 10+)."""
    files_str = format_packed_string_array(export_files)
    return f"""
[preset.2]

name="Windows Desktop"
platform="Windows Desktop"
runnable=true
dedicated_server=false
custom_features=""
export_filter="resources"
export_files={files_str}
include_filter=""
exclude_filter=""
export_path="dist/AtomZero.exe"
patches=PackedStringArray()
patch_delta_encoding=false
patch_delta_compression_level_zstd=19
patch_delta_min_reduction=0.1
patch_delta_include_filters="*"
patch_delta_exclude_filters=""
encryption_include_filters=""
encryption_exclude_filters=""
seed=0
encrypt_pck=false
encrypt_directory=false
script_export_mode=2

[preset.2.options]

custom_template/debug=""
custom_template/release=""
debug/export_console_wrapper=1
binary_format/architecture="x86_64"
binary_format/embed_pck=false
texture_format/s3tc=true
texture_format/etc2=false
codesign/enable=false
codesign/timestamp=""
codesign/timestamp_server=""
codesign/digest_algorithm=""
codesign/description=""
codesign/custom_options=PackedStringArray()
application/modify_resources=true
application/icon=""
application/console_wrapper_icon=""
application/icon_interpolation=4
application/file_version="{version}"
application/product_version="{version}"
application/company_name="AtomLife Studio"
application/product_name="AtomZero"
application/file_description="AtomZero"
application/copyright="© 2026 AtomLife Studio. All rights reserved."
application/trademarks=""
application/export_angle=0
ssh_remote_deploy/enabled=false
ssh_remote_deploy/host="user@host_ip"
ssh_remote_deploy/port="22"
ssh_remote_deploy/extra_args_ssh=""
ssh_remote_deploy/extra_args_scp=""
ssh_remote_deploy/run_script="Expand-Archive -Path \\"{{temp_dir}}\\\\{{archive_name}}\\" -DestinationPath \\"{{temp_dir}}\\"\\n$exit_code = Start-Process -FilePath \\"{{temp_dir}}\\\\{{exe_name}}\\" -ArgumentList \\"{{cmd_args}}\\" -Wait -NoNewWindow -PassThru\\nExit-Code $exit_code"
ssh_remote_deploy/cleanup_script="Stop-Process -Name \\"{{exe_name}}\\" -ErrorAction SilentlyContinue\\nRemove-Item -Recurse -Force \\"{{temp_dir}}\\""
"""


def generate_android_preset(version: str, export_files: list) -> str:
    """Generate the Android preset (targeting Android 9+, API 28+)."""
    files_str = format_packed_string_array(export_files)
    return f"""
[preset.3]

name="Android"
platform="Android"
runnable=true
dedicated_server=false
custom_features=""
export_filter="resources"
export_files={files_str}
include_filter=""
exclude_filter=""
export_path="dist/AtomZero.apk"
patches=PackedStringArray()
patch_delta_encoding=false
patch_delta_compression_level_zstd=19
patch_delta_min_reduction=0.1
patch_delta_include_filters="*"
patch_delta_exclude_filters=""
encryption_include_filters=""
encryption_exclude_filters=""
seed=0
encrypt_pck=false
encrypt_directory=false
script_export_mode=2

[preset.3.options]

custom_template/debug=""
custom_template/release=""
gradle_build/export_format=0
gradle_build/min_sdk=28
gradle_build/target_sdk=34
architectures/armeabi-v7a=true
architectures/arm64-v8a=true
architectures/x86=false
architectures/x86_64=false
keystore/debug=""
keystore/debug_user=""
keystore/debug_password=""
keystore/release=""
keystore/release_user=""
keystore/release_password=""
keystore/export_project_files=true
one_click_deploy/clear_previous_install=false
permissions/custom_permissions=PackedStringArray()
permissions/microphone=false
permissions/camera=false
permissions/vibrate=false
permissions/tethered_camera=false
permissions/network_test_access_state=false
permissions/bluetooth=false
permissions/network_state_access=false
permissions/storage_read_access=false
permissions/storage_write_access=false
permissions/manage_external_storage=false
permissions/install_unknown_sources=false
application/enable_longwise_gravity_sensor=false
application/bundle_identifier="com.atom.zero"
application/version="1.0.0"
application/version_code=1
application/short_version="{version}"
application/show_in_android_tv=false
application/show_in_app_store=true
application/retain_data_on_uninstall=false
application/uses_steam=false
application/export_angle=0
launcher_icons/main_192x192=""
launcher_icons/adaptive_foreground_432x432=""
launcher_icons/adaptive_background_432x432=""
launcher_icons/main_512x512=""
graphics/opengl_debug=false
xr_features/xr_mode=0
xr_features/hand_tracking=0
xr_features/hand_tracking_version=0
xr_features/passthrough=0
xr_features/immersive_mr=0
screen/immersive_mode=true
screen/support_small=true
screen/support_normal=true
screen/support_large=true
screen/support_xlarge=true
user_plugins/PackedStringArray=[]
gradle_build/compress_native_libraries=false
gradle_build/extract_native_libs=false
gradle_build/use_gradle_build=true
gradle_build/gradle_build_path="android://build"
package/unique_name="com.atom.zero"
package/signed=true
package/app_category="game"
package/retain_data_on_uninstall=false
package/exclude_from_recents=false
package/show_in_android_tv=false
package/show_in_app_store=true
package/export_files_only=false
launcher_icons/enable_adaptive=false
"""


def generate_ios_preset(version: str, export_files: list) -> str:
    """Generate the iOS preset (targeting iOS 14+)."""
    files_str = format_packed_string_array(export_files)
    return f"""
[preset.4]

name="iOS"
platform="iOS"
runnable=true
dedicated_server=false
custom_features=""
export_filter="resources"
export_files={files_str}
include_filter=""
exclude_filter=""
export_path="dist/AtomZero.ipa"
patches=PackedStringArray()
patch_delta_encoding=false
patch_delta_compression_level_zstd=19
patch_delta_min_reduction=0.1
patch_delta_include_filters="*"
patch_delta_exclude_filters=""
encryption_include_filters=""
encryption_exclude_filters=""
seed=0
encrypt_pck=false
encrypt_directory=false
script_export_mode=2

[preset.4.options]

custom_template/debug=""
custom_template/release=""
architectures/arm64=true
application/app_store_team_id="0000000000"
application/bundle_identifier="com.atom.zero"
application/signing_method=0
application/certificate=""
application/certificate_password=""
application/provisioning_profile=""
application/export_method=2
application/targeted_device_family=2
application/short_version="{version}"
application/version="{version}"
application/export_angle=0
application/privacy_microphone_usage_description=""
application/privacy_camera_usage_description=""
application/privacy_photos_library_usage_description=""
application/privacy_files_downloads_usage_description=""
application/icon_interpolation=4
application/launch_screens_interpolation=4
application/export_project_only=false
application/delete_old_export_files_universally=false
application/launch_screen_image=""
application/launch_screen_fill_mode=0
application/launch_screen_minimum_system_version="14.0"
capabilities/arkit=false
capabilities/camera=false
capabilities/access_wifi=false
capabilities/game_center=false
capabilities/in_app_purchases=false
capabilities/multitasking=false
capabilities/performance_gaming_controller=false
capabilities/performance_gaming_controller_motion=false
capabilities/push_notifications=false
capabilities/user_notifications=false
capabilities/webview=false
xr/arkit_tracking_type=0
xr/face_tracking=false
xr/face_tracking_facing_camera=0
xr/location_tracking=false
user_data/accessible_from_files_app=false
user_data/accessible_from_itunes_sharing=false
privacy/microphone_usage_description=""
privacy/microphone_usage_description_localized={{}}
privacy/camera_usage_description=""
privacy/camera_usage_description_localized={{}}
privacy/photos_library_usage_description=""
privacy/photos_library_usage_description_localized={{}}
privacy/files_downloads_usage_description=""
privacy/files_downloads_usage_description_localized={{}}
privacy/tracking_enabled=false
privacy/tracking_domains=PackedStringArray()
ssh_remote_deploy/enabled=false
ssh_remote_deploy/host="user@host_ip"
ssh_remote_deploy/port="22"
ssh_remote_deploy/extra_args_ssh=""
ssh_remote_deploy/extra_args_scp=""
"""


PRESET_GENERATORS = [
    generate_macos_preset,
    generate_linux_preset,
    generate_windows_preset,
    generate_android_preset,
    generate_ios_preset,
]


def main():
    parser = argparse.ArgumentParser(
        description="Generate export_presets.cfg for AtomZero (all platforms)."
    )
    parser.add_argument(
        "--version",
        help="Override the game version (default: read from project.godot)",
    )
    parser.add_argument(
        "--output",
        default="export_presets.cfg",
        help="Output path (default: export_presets.cfg in project root)",
    )
    args = parser.parse_args()

    project_root = find_project_root()

    version = args.version or get_version_from_project(project_root)
    export_files = scan_export_files(project_root)

    print(f"[generate_export_presets] Game version: {version}")
    print(f"[generate_export_presets] Export files ({len(export_files)}):")
    for f in export_files:
        print(f"  {f}")

    parts = [
        "; Auto-generated by tools/ci/generate_export_presets.py",
        "; DO NOT EDIT MANUALLY — regenerate with: python3 tools/ci/generate_export_presets.py",
        f"; Game version: {version}",
        "",
        f"[preset._defaults]",
        "",
        f"binary_format/embed_pck=false",
        "",
    ]

    for generator in PRESET_GENERATORS:
        parts.append(generator(version, export_files))

    content = "\n".join(parts)

    output_path = Path(args.output)
    if not output_path.is_absolute():
        output_path = project_root / output_path

    with open(output_path, "w", encoding="utf-8") as f:
        f.write(content)

    print(f"[generate_export_presets] Wrote {output_path}")
    print(f"[generate_export_presets] Presets: macOS, Linux, Windows Desktop, Android, iOS")


if __name__ == "__main__":
    main()
