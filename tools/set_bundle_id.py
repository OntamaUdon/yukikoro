"""Bundle ID（と Team ID）を、プロジェクト内の全ての場所でまとめて書き換える。

使い方:
    python tools/set_bundle_id.py com.yourname.yukikoro
    python tools/set_bundle_id.py com.yourname.yukikoro --team ABCDE12345
    python tools/set_bundle_id.py com.yourname.yukikoro --dry-run      # 書き換えずに内容だけ確認

Bundle ID は世界で1つだけの名前（逆さにしたドメイン形式）。例: com.taro.yukikoro
 - アプリ本体      : <指定したID>
 - ウィジェット    : <指定したID>.widget
 - テスト          : <指定したID>.tests
 - App Group       : group.<指定したID>
書き換え後に Xcode で開き直してください（XcodeGen を入れている場合は `xcodegen generate` でもよい）。
"""
import argparse
import os
import re
import sys

OLD = "com.example.yukikoro"
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
FILES = [
    "project.yml",
    "Shared/Storage.swift",
    "App/Yukikoro.entitlements",
    "Widget/YukikoroWidget.entitlements",
    "Yukikoro.xcodeproj/project.pbxproj",
    "tools/screenshots.sh",
]

parser = argparse.ArgumentParser()
parser.add_argument("bundle_id")
parser.add_argument("--team", help="Apple Developer の Team ID（10文字の英数字）")
parser.add_argument("--dry-run", action="store_true")
args = parser.parse_args()

new = args.bundle_id.strip()
if not re.fullmatch(r"[a-z0-9]([a-z0-9\-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9\-]*[a-z0-9])?)+", new):
    sys.exit("Bundle ID は、小文字の英数字とハイフンを、ドットでつないだ形にしてください（例: com.taro.yukikoro）")
if new.startswith("com.example."):
    sys.exit("com.example. で始まる ID は仮のものです。自分の名前などに変えてください")
if args.team and not re.fullmatch(r"[A-Z0-9]{10}", args.team):
    sys.exit("Team ID は大文字英数字10文字です（例: ABCDE12345）")

changed = 0
for rel in FILES:
    path = os.path.normpath(os.path.join(ROOT, rel))
    if not os.path.exists(path):
        print("（無いのでスキップ）", rel)
        continue
    text = open(path, encoding="utf-8").read()
    out = text.replace(OLD, new)
    if args.team:
        out = re.sub(r'DEVELOPMENT_TEAM: ""', f"DEVELOPMENT_TEAM: {args.team}", out)
        out = re.sub(r'DEVELOPMENT_TEAM = "";', f"DEVELOPMENT_TEAM = {args.team};", out)
    n = out.count(new) - text.count(new)
    if out != text:
        changed += 1
        print(("[dry-run] " if args.dry_run else "") + f"書き換え: {rel}")
        if not args.dry_run:
            open(path, "w", encoding="utf-8", newline="\n").write(out)
    else:
        print("変更なし:", rel)

print()
print(f"{changed} ファイルを{'書き換える予定です' if args.dry_run else '書き換えました'}。")
print(f"  アプリ     : {new}")
print(f"  ウィジェット: {new}.widget")
print(f"  App Group  : group.{new}")
