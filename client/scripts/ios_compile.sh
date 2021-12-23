#!/bin/bash


. $(dirname $0)/commons.sh

if [ -f .env ]; then
  . .env
fi

RELEASE=1
OS=
NETWORKEXTENSION=
ADJUST_SDK_TOKEN=
ADJUST="CONFIG-=adjust"

helpFunction() {
  print G "Usage:"
  print N "\t$0 <ios> [-d|--debug] [-n|--networkextension] [-a|--adjusttoken <adjust_token>]"
  print N ""
  print N "By default, the project is compiled in release mode. Use -d or --debug for a debug build."
  print N "Use -n or --networkextension to force the network-extension component for MacOS too."
  print N ""
  print N "If MVPN_IOS_ADJUST_TOKEN env is found, this will be used at compilation time."
  print N ""
  print G "Config variables:"
  print N "\tQT_MACOS_BIN=</path/of/the/qt/bin/folder/for/macos>"
  print N "\tQT_IOS_BIN=</path/of/the/qt/bin/folder/for/ios>"
  print N "\tMVPN_IOS_ADJUST_TOKEN=<token>"
  print N ""
  exit 0
}

print N "This script compiles AmneziaVPN for MacOS/iOS"
print N ""

#export QT_IOS_BIN="$HOME/Qt/5.15.2/ios/bin"
#export PATH=$QT_IOS_BIN:$PATH

while [[ $# -gt 0 ]]; do
  key="$1"

  case $key in
  -a | --adjusttoken)
    ADJUST_SDK_TOKEN="$2"
    shift
    shift
    ;;
  -d | --debug)
    RELEASE=
    shift
    ;;
  -n | --networkextension)
    NETWORKEXTENSION=1
    shift
    ;;
  -h | --help)
    helpFunction
    ;;
  *)
    if [[ "$OS" ]]; then
      helpFunction
    fi

    OS=$1
    shift
    ;;
  esac
done

fetch() {
  if command -v "wget" &>/dev/null; then
    wget -nc -O "$2" "$1"
    return
  fi

  if command -v "curl" &>/dev/null; then
    curl "$1" -o "$2" -s -L
    return
  fi

  die "You must have 'wget' or 'curl' installed."
}

sha256() {
  if command -v "sha256sum" &>/dev/null; then
    sha256sum "$1"
    return 0
  fi

  if command -v "openssl" &>/dev/null; then
    openssl dgst -sha256 "$1"
    return 0
  fi

  die "You must have 'sha256sum' or 'openssl' installed."
}

if [[ "$OS" != "macos" ]] && [[ "$OS" != "ios" ]] && [[ "$OS" != "macostest" ]]; then
  helpFunction
fi

if ! [[ "$ADJUST_SDK_TOKEN" ]] && [[ "$MVPN_IOS_ADJUST_TOKEN" ]]; then
  print Y "Using the MVPN_IOS_ADJUST_TOKEN value for the adjust token"
  ADJUST_SDK_TOKEN=$MVPN_IOS_ADJUST_TOKEN
fi

if [[ "$OS" == "ios" ]]; then
  # Network-extension is the default for IOS
  NETWORKEXTENSION=1
fi

if ! [ -d "ios" ] || ! [ -d "macos" ]; then
  die "This script must be executed at the root of the repository."
fi

QMAKE=qmake
if [ "$OS" = "macos" ] && ! [ "$QT_MACOS_BIN" = "" ]; then
  QMAKE=$QT_MACOS_BIN/qmake
elif [ "$OS" = "macostest" ] && ! [ "$QT_MACOS_BIN" = "" ]; then
  QMAKE=$QT_MACOS_BIN/qmake
elif [ "$OS" = "ios" ] && ! [ "$QT_IOS_BIN" = "" ]; then
  QMAKE=$QT_IOS_BIN/qmake
fi

$QMAKE -v &>/dev/null || die "qmake doesn't exist or it fails"

printn Y "Retrieve the wireguard-go version... "
(cd macos/gobridge && go list -m golang.zx2c4.com/wireguard | sed -n 's/.*v\([0-9.]*\).*/#define WIREGUARD_GO_VERSION "\1"/p') > macos/gobridge/wireguard-go-version.h
print G "done."

printn Y "Cleaning the existing project... "
rm -rf AmneziaVPN.xcodeproj/ || die "Failed to remove things"
print G "done."

#print Y "Importing translation files..."
#git submodule update --remote --depth 1 i18n || die "Failed to fetch newest translation files"
#python scripts/importLanguages.py $([[ "$OS" = "macos" ]] && echo "-m" || echo "") || die "Failed to import languages"
#
#print Y "Generating glean samples..."
#python scripts/generate_glean.py || die "Failed to generate glean samples"

printn Y "Extract the project version... "
#SHORTVERSION=$(cat version.pri | grep VERSION | grep defined | cut -d= -f2 | tr -d \ )
#FULLVERSION=$(echo $SHORTVERSION | cut -d. -f1).$(date +"%Y%m%d%H%M")
SHORTVERSION=$(cat version.pri | grep VERSION | grep defined | cut -d= -f2 | tr -d \ )
FULLVERSION=$(cat versionfull.pri | grep BUILDVERSION | grep defined | cut -d= -f2 | tr -d \ )
print G "$SHORTVERSION - $FULLVERSION"

MACOS_FLAGS="
  QTPLUGIN+=qsvg
  CONFIG-=static
  CONFIG+=balrog
  MVPN_MACOS=1
"

MACOSTEST_FLAGS="
  QTPLUGIN+=qsvg
  CONFIG-=static
  CONFIG+=DUMMY
"

IOS_FLAGS="
  MVPN_IOS=1
  Q_OS_IOS=1
"

printn Y "Mode: "
if [[ "$RELEASE" ]]; then
  print G "release"
  MODE="CONFIG-=debug CONFIG+=release CONFIG-=debug_and_release"
else
  print G "debug"
  MODE="CONFIG+=debug CONFIG-=release CONFIG-=debug_and_release"
fi

OSRUBY=$OS
printn Y "OS: "
print G "$OS"
if [ "$OS" = "macos" ]; then
  PLATFORM=$MACOS_FLAGS
elif [ "$OS" = "macostest" ]; then
  OSRUBY=macos
  PLATFORM=$MACOSTEST_FLAGS
elif [ "$OS" = "ios" ]; then
  PLATFORM=$IOS_FLAGS
  if [[ "$ADJUST_SDK_TOKEN"  ]]; then
    printn Y "ADJUST_SDK_TOKEN: "
    print G "$ADJUST_SDK_TOKEN"
    ADJUST="CONFIG+=adjust"
  fi
else
  die "Why we are here?"
fi

VPNMODE=
printn Y "VPN mode: "
if [[ "$NETWORKEXTENSION" ]]; then
  print G network-extension
  VPNMODE="CONFIG+=networkextension"
else
  print G daemon
fi

printn Y "Web-Extension: "
WEMODE=
if [ "$OS" = "macos" ]; then
  print G web-extension
  WEMODE="CONFIG+=webextension"
else
  print G none
fi

if [ "$OS" = "ios" ]; then
  print Y "Prepare to build OpenVPNAdapter..."
  prepare_to_build_vpn
  print Y "Building OpenVPNAdapter..."
  compile_openvpn_adapter
else
  print Y "No OpenVPNAdapter will be built"
fi

if [ "$OS" = "ios" ]; then
  print Y "Prepare to build ShadowSocks..."
  prepare_to_build_ss
  print Y "Patching the ShadowSocks project..."
  patch_ss
  ruby ../../scripts/ss_project_patcher.rb "ShadowSocks.xcodeproj"
  print G "done."
  print Y "Building ShadowSocks Framework..."
  compile_ss_frameworks
else
  print Y "No ShadowSocket Library will be built"
fi

#if [ "$OS" = "ios" ]; then
# print Y "Prepare to build Packet Processor..."
# prepare_to_build_pp
# print Y "Building PacketProcessor Framework..."
# compile_packet_processor
#else
# print Y "No Packet Processor will be built"
#fi

print Y "Creating the xcode project via qmake..."
$QMAKE \
  VERSION=$SHORTVERSION \
  BUILD_ID=$FULLVERSION \
  -spec macx-xcode \
  $MODE \
  $VPNMODE \
  $WEMODE \
  $PLATFORM \
  $ADJUST \
  ./client.pro || die "Compilation failed"

print Y "Patching the xcode project..."
ruby scripts/xcode_patcher.rb "AmneziaVPN.xcodeproj" "$SHORTVERSION" "$FULLVERSION" "$OSRUBY" "$NETWORKEXTENSION" "$ADJUST_SDK_TOKEN" || die "Failed to merge xcode with wireguard"
print G "done."

  if command -v "sed" &>/dev/null; then
    sed -i '' '/<key>BuildSystemType<\/key>/d' AmneziaVPN.xcodeproj/project.xcworkspace/xcshareddata/WorkspaceSettings.xcsettings
    sed -i '' '/<string>Original<\/string>/d' AmneziaVPN.xcodeproj/project.xcworkspace/xcshareddata/WorkspaceSettings.xcsettings
  fi

print Y "Opening in XCode..."
open AmneziaVPN.xcodeproj
print G "All done!"
