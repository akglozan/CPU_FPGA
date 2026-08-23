#!/usr/bin/env python3
import os

AUTHOR = "Ozan Akgül"
YEAR = "2026"

# Template with comment prefix placeholder
HEADER_TEMPLATE = """{c} SPDX-License-Identifier: Apache-2.0
{c} Copyright {year} {author}
{c}
{c} Licensed under the Apache License, Version 2.0 (the "License");
{c} you may not use this file except in compliance with the License.
{c} You may obtain a copy of the License at
{c}
{c}     http://www.apache.org/licenses/LICENSE-2.0
{c}
{c} Unless required by applicable law or agreed to in writing, software
{c} distributed under the License is distributed on an "AS IS" BASIS,
{c} WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
{c} See the License for the specific language governing permissions and
{c} limitations under the License.
"""

# File extensions mapped to their single-line comment syntax
EXT_MAP = {
    ".v": "//",
    ".sv": "//",
    ".c": "//",
    ".h": "//",
    ".cpp": "//",
    ".vhd": "--",
    ".vhdl": "--",
    ".py": "#",
    ".tcl": "#",
    ".sh": "#",
}

# Directories to ignore
IGNORED_DIRS = {".git", ".github", "runs", "build", "target", "__pycache__", "venv"}


def format_header(comment_char):
    return HEADER_TEMPLATE.format(c=comment_char, year=YEAR, author=AUTHOR)


def process_file(filepath, comment_char):
    with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
        content = f.read()

    # Skip if SPDX identifier or Apache license is already present
    if "SPDX-License-Identifier" in content or "Apache License" in content:
        print(f"Skipping (already licensed): {filepath}")
        return

    header = format_header(comment_char)

    # Preserve shebang line if present in scripts
    if content.startswith("#!"):
        lines = content.split("\n", 1)
        shebang = lines[0] + "\n\n"
        rest = lines[1] if len(lines) > 1 else ""
        new_content = shebang + header + "\n" + rest
    else:
        new_content = header + "\n" + content

    with open(filepath, "w", encoding="utf-8") as f:
        f.write(new_content)

    print(f"Updated: {filepath}")


def main():
    root_dir = "."
    for root, dirs, files in os.walk(root_dir):
        dirs[:] = [d for d in dirs if d not in IGNORED_DIRS]

        for file in files:
            ext = os.path.splitext(file)[1].lower()
            if ext in EXT_MAP:
                process_file(os.path.join(root, file), EXT_MAP[ext])
            elif file.lower() == "makefile":
                process_file(os.path.join(root, file), "#")


if __name__ == "__main__":
    main()