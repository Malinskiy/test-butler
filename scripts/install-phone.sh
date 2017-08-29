#!/usr/bin/env bash
# Downloads test-butler apk, patches the services.jar from connected android devices and installs test-butler
#
# Requires in path:
# - wget
# - apktool
# - adb
# - GNU sed

url=${1:-"https://bintray.com/linkedin/maven/download_file?file_path=com%2Flinkedin%2Ftestbutler%2Ftest-butler-app%2F1.3.1%2Ftest-butler-app-1.3.1.apk"}

rm -Rf build/phone

function download_app() {
  if [ ! -f "prebuilt/test-butler-app.apk" ]
  then
    mkdir -p prebuilt
    wget -O prebuilt/test-butler-app.apk $url
  fi
}

function download_services() {
  mkdir -p build

  if [ `adb shell "if [ ! -f /system/framework/services.jar.backup ]; then echo 1; fi"` ]; then
    adb pull /system/framework/services.jar build/services.jar
  else
    adb shell su -c 'cp /system/framework/services.jar.backup /sdcard/services.jar'
    adb pull /sdcard/services.jar build/services.jar
    adb shell su -c 'rm /sdcard/services.jar'
  fi
}

function patch_services() {
  apktool d -f -o build/src/services build/services.jar
  sed -n -i '/\.method private grantSignaturePermission/{p;:a;N;/\.end method/!ba;s/.*\n/\t\.locals 1\n\tconst\/4 v0, 0x1\n\treturn v0 \n/};p' build/src/services/smali/com/android/server/pm/PackageManagerService.smali
  apktool b -f -o build/patched/services.jar build/src/services
}

function backup() {
  if [ `adb shell "if [ ! -f /system/framework/services.jar.backup ]; then echo 1; fi"` ]; then
   adb shell su -c 'cp /system/framework/services.jar /system/framework/services.jar.backup'
  fi
}

function prepare_to_install() {
  adb wait-for-device
  adb shell 'su -c mount -o rw,remount /system'
  backup
}

function install_app() {
  adb push prebuilt/test-butler-app.apk /sdcard/
  adb shell su -c 'mv /sdcard/test-butler-app.apk /system/priv-app/'
  adb shell su -c 'chmod 644 /system/priv-app/test-butler-app.apk'
}

function install_services() {
  adb push build/patched/services.jar /sdcard/
  adb shell su -c 'mv /sdcard/services.jar /system/framework/'
  adb shell su -c 'chown root:root /system/framework/services.jar'
  adb shell su -c 'chmod 644 /system/framework/services.jar'
}

function restart_vm() {
  adb shell su -c 'stop'
  adb shell su -c 'start'
}

download_app
download_services

patch_services

prepare_to_install
install_app
install_services

restart_vm
