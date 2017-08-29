#!/usr/bin/env bash
# Requires in path:
# - wget
# - java
# - apktool
# - adb


url=${1:-"https://bintray.com/linkedin/maven/download_file?file_path=com%2Flinkedin%2Ftestbutler%2Ftest-butler-app%2F1.3.1%2Ftest-butler-app-1.3.1.apk"}

rm -Rf build/phone

function download_app() {
  if [ ! -f "prebuilt/test-butler-app.apk" ]
  then
    mkdir -p prebuilt
    wget -O prebuilt/test-butler-app.apk $url
  fi

  mkdir -p build/phone
  cp prebuilt/test-butler-app.apk build/phone/test-butler-app.apk
}

function download_services() {
  if [ `adb shell "if [ ! -f /system/framework/services.jar.backup ]; then echo 1; fi"` ]; then
    adb pull /system/framework/services.jar build/phone/services.jar
  else
    adb shell su -c 'cp /system/framework/services.jar.backup /sdcard/services.jar'
    adb pull /sdcard/services.jar build/phone/services.jar
    adb shell su -c 'rm /sdcard/services.jar'
  fi
}

function patch_app() {
  apktool d -f -o build/phone/src/app build/phone/test-butler-app.apk
  sed -i 's/android:sharedUserId="android.uid.system"//g' build/phone/src/app/AndroidManifest.xml
  apktool b -f -o build/phone/patched/test-butler-app.apk build/phone/src/app
}

function sign_app() {
  if [ ! -f "prebuilt/sign.jar" ]
  then
    mkdir -p libs
    wget -O prebuilt/sign.jar https://raw.githubusercontent.com/appium/sign/master/dist/sign.jar
  fi

  java -jar prebuilt/sign.jar build/phone/patched/test-butler-app.apk --override
}

function patch_services() {
  apktool d -f -o build/phone/src/services build/phone/services.jar
  sed -n -i '/\.method private grantSignaturePermission/{p;:a;N;/\.end method/!ba;s/.*\n/\t\.locals 1\n\tconst\/4 v0, 0x1\n\treturn v0 \n/};p' build/phone/src/services/smali/com/android/server/pm/PackageManagerService.smali
  apktool b -f -o build/phone/patched/services.jar build/phone/src/services
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
  adb push build/phone/patched/test-butler-app.apk /sdcard/
  adb shell su -c 'mv /sdcard/test-butler-app.apk /system/priv-app/'
  adb shell su -c 'chmod 644 /system/priv-app/test-butler-app.apk'
}

function install_services() {
  adb push build/phone/patched/services.jar /sdcard/
  adb shell su -c 'mv /sdcard/services.jar /system/framework/'
  adb shell su -c 'chown root:root /system/framework/services.jar'
  adb shell su -c 'chmod 644 /system/framework/services.jar'
}

function restart_vm() {
  adb shell su -c 'stop'
  adb shell su -c 'start'
}

download_app
patch_app
sign_app

download_services
patch_services

prepare_to_install

install_app
install_services

restart_vm
