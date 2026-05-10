#!/usr/bin/env python3
"""
patch_pbxproj.py
────────────────
Patches an Xcode project.pbxproj in-place to:
  1. Add a PBXFileReference for libmgba.a
  2. Add a PBXBuildFile (Frameworks phase) linking it
  3. Add HEADER_SEARCH_PATHS pointing to mgba headers
  4. Add LIBRARY_SEARCH_PATHS pointing to libmgba.a directory
  5. Add OTHER_LDFLAGS: -lmgba -lz -lc++

Works by text-patching the pbxproj (Apple's ASCII plist format).
Idempotent — running twice produces the same result.

Usage:
  python3 scripts/patch_pbxproj.py \
    --pbxproj   GBALinkEmulator.xcodeproj/project.pbxproj \
    --lib-path  /abs/path/to/mgba-dist/lib/libmgba.a \
    --inc-path  /abs/path/to/mgba-dist/include
"""

import argparse
import os
import re
import sys

# ── Stable fake UUIDs (hex, 24 chars like Xcode generates) ──────────────────
UUID_FILE_REF   = "BB0MGBA000000000000001A"   # PBXFileReference for libmgba.a
UUID_BUILD_FILE = "BB0MGBA000000000000001B"   # PBXBuildFile for libmgba.a

# ── Known UUIDs from the project (from project.pbxproj) ─────────────────────
UUID_FRAMEWORKS_PHASE = "AA0100E1000000000000001A"  # PBXFrameworksBuildPhase


def read(path: str) -> str:
    with open(path, "r", encoding="utf-8") as f:
        return f.read()


def write(path: str, content: str) -> None:
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)


def already_patched(content: str) -> bool:
    return UUID_FILE_REF in content


def inject_file_reference(content: str, lib_abs: str) -> str:
    """Add PBXFileReference for libmgba.a after the existing file references section."""
    new_ref = (
        f"\t\t{UUID_FILE_REF} /* libmgba.a */ = "
        f"{{isa = PBXFileReference; lastKnownFileType = archive.ar; "
        f"name = libmgba.a; path = \"{lib_abs}\"; sourceTree = \"<absolute>\"; }};\n"
    )
    # Insert right before "End PBXFileReference section"
    marker = "/* End PBXFileReference section */"
    assert marker in content, f"Marker not found: {marker}"
    return content.replace(marker, new_ref + "\t\t" + marker)


def inject_build_file(content: str) -> str:
    """Add PBXBuildFile for libmgba.a."""
    new_bf = (
        f"\t\t{UUID_BUILD_FILE} /* libmgba.a in Frameworks */ = "
        f"{{isa = PBXBuildFile; fileRef = {UUID_FILE_REF} /* libmgba.a */; "
        f"settings = {{ATTRIBUTES = (); }}; }};\n"
    )
    marker = "/* End PBXBuildFile section */"
    assert marker in content, f"Marker not found: {marker}"
    return content.replace(marker, new_bf + "\t\t" + marker)


def inject_into_frameworks_phase(content: str) -> str:
    """Add the build file reference into the Frameworks build phase files list."""
    # Find the Frameworks phase block
    phase_pattern = re.compile(
        r"(" + re.escape(UUID_FRAMEWORKS_PHASE) + r"[^{]*\{[^}]*?files\s*=\s*\()(.*?)(\);)",
        re.DOTALL
    )
    new_entry = f"\n\t\t\t\t{UUID_BUILD_FILE} /* libmgba.a in Frameworks */,"

    def replacer(m):
        # Avoid double-insertion
        if UUID_BUILD_FILE in m.group(0):
            return m.group(0)
        return m.group(1) + new_entry + m.group(2) + m.group(3)

    patched, count = phase_pattern.subn(replacer, content)
    assert count > 0, "Could not find Frameworks build phase to inject into"
    return patched


def inject_build_settings(content: str, inc_abs: str, lib_dir: str) -> str:
    """
    Inject HEADER_SEARCH_PATHS, LIBRARY_SEARCH_PATHS, and OTHER_LDFLAGS
    into BOTH Debug and Release target build configurations.

    Strategy: find each XCBuildConfiguration block for the target (the ones
    that contain PRODUCT_BUNDLE_IDENTIFIER) and insert our settings before
    the closing };
    """
    settings_block = (
        f'\t\t\t\tHEADER_SEARCH_PATHS = (\n'
        f'\t\t\t\t\t"$(inherited)",\n'
        f'\t\t\t\t\t"{inc_abs}",\n'
        f'\t\t\t\t\t"{inc_abs}/mgba",\n'
        f'\t\t\t\t);\n'
        f'\t\t\t\tLIBRARY_SEARCH_PATHS = (\n'
        f'\t\t\t\t\t"$(inherited)",\n'
        f'\t\t\t\t\t"{lib_dir}",\n'
        f'\t\t\t\t);\n'
        f'\t\t\t\tOTHER_LDFLAGS = (\n'
        f'\t\t\t\t\t"$(inherited)",\n'
        f'\t\t\t\t\t"-lmgba",\n'
        f'\t\t\t\t\t"-lz",\n'
        f'\t\t\t\t\t"-lc++",\n'
        f'\t\t\t\t);\n'
    )

    # We target XCBuildConfiguration blocks that contain PRODUCT_BUNDLE_IDENTIFIER
    # (those are the target-level configs, not the project-level ones).
    # Pattern: from "AA0100C2..." or "AA0100C3..." block start to its closing };
    config_pattern = re.compile(
        r'(AA0100C[23]000000000000001A\s*/\*.*?\*/\s*=\s*\{)'
        r'(\s*isa\s*=\s*XCBuildConfiguration;)'
        r'(.*?)'
        r'(\s*\};)',
        re.DOTALL
    )

    def replacer(m):
        block = m.group(3)
        # Skip if already patched
        if "HEADER_SEARCH_PATHS" in block and "libmgba" in block:
            return m.group(0)
        # Remove any pre-existing bare HEADER_SEARCH_PATHS/LIBRARY_SEARCH_PATHS
        # so we don't duplicate (idempotency)
        block = re.sub(r'\s*HEADER_SEARCH_PATHS\s*=[^;]+;', '', block)
        block = re.sub(r'\s*LIBRARY_SEARCH_PATHS\s*=[^;]+;', '', block)
        block = re.sub(r'\s*OTHER_LDFLAGS\s*=[^;]+;', '', block)
        return (
            m.group(1) + m.group(2) + block +
            "\n" + settings_block +
            m.group(4)
        )

    patched, count = config_pattern.subn(replacer, content)
    if count == 0:
        # Fallback: try simpler approach — insert before each SWIFT_VERSION line
        # inside target configs
        print("WARNING: Primary config injection found 0 matches, trying fallback")
        swift_pattern = re.compile(
            r'(PRODUCT_BUNDLE_IDENTIFIER\s*=\s*[^;]+;.*?)(SWIFT_VERSION\s*=\s*[^;]+;)',
            re.DOTALL
        )
        patched, count = swift_pattern.subn(
            lambda m: m.group(1) + settings_block + m.group(2),
            content
        )
        print(f"Fallback injection: {count} replacements")

    return patched


def main():
    parser = argparse.ArgumentParser(description="Patch pbxproj to link libmgba.a")
    parser.add_argument("--pbxproj",  required=True, help="Path to project.pbxproj")
    parser.add_argument("--lib-path", required=True, help="Absolute path to libmgba.a")
    parser.add_argument("--inc-path", required=True, help="Absolute path to include/ dir")
    args = parser.parse_args()

    pbxproj  = os.path.abspath(args.pbxproj)
    lib_abs  = os.path.abspath(args.lib_path)
    inc_abs  = os.path.abspath(args.inc_path)
    lib_dir  = os.path.dirname(lib_abs)

    print(f"Patching:  {pbxproj}")
    print(f"Library:   {lib_abs}")
    print(f"Headers:   {inc_abs}")

    if not os.path.exists(pbxproj):
        print(f"ERROR: pbxproj not found: {pbxproj}", file=sys.stderr)
        sys.exit(1)
    if not os.path.exists(lib_abs):
        print(f"ERROR: libmgba.a not found: {lib_abs}", file=sys.stderr)
        sys.exit(1)
    if not os.path.isdir(inc_abs):
        print(f"ERROR: include dir not found: {inc_abs}", file=sys.stderr)
        sys.exit(1)

    content = read(pbxproj)

    if already_patched(content):
        # Only re-patch settings if the paths differ (e.g. workspace moved)
        if inc_abs in content and lib_dir in content:
            print("✅ pbxproj already patched with current paths. Nothing to do.")
            return
        print("✅ pbxproj already patched — updating paths.")
        content = inject_build_settings(content, inc_abs, lib_dir)
        write(pbxproj, content)
        print("Done (paths updated).")
        return

    # Apply patches in order
    content = inject_file_reference(content, lib_abs)
    content = inject_build_file(content)
    content = inject_into_frameworks_phase(content)
    content = inject_build_settings(content, inc_abs, lib_dir)

    write(pbxproj, content)
    print("✅ pbxproj patched successfully.")

    # Quick sanity check
    result = read(pbxproj)
    checks = [
        (UUID_FILE_REF,   "PBXFileReference"),
        (UUID_BUILD_FILE, "PBXBuildFile"),
        ("libmgba",       "library name"),
        ("HEADER_SEARCH", "header search paths"),
        ("-lmgba",        "linker flag"),
    ]
    all_ok = True
    for token, label in checks:
        if token in result:
            print(f"  ✓ {label}")
        else:
            print(f"  ✗ {label} MISSING", file=sys.stderr)
            all_ok = False

    sys.exit(0 if all_ok else 1)


if __name__ == "__main__":
    main()
