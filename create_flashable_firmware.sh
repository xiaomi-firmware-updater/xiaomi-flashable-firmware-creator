#!/bin/bash

if [ -z $1 ]; then
    echo "Usage: create_flashable_firmware.sh ROM_FILE"
    exit 1
fi

if [ ! -f $1 ]; then
    echo "** File not available."
    exit 1
fi

MIUI_ZIP_NAME=$(basename $1)
MIUI_ZIP_DIR=$(dirname $1)

if [ ! -z ${2+x} ]; then
    OUTPUT_DIR=$2
else
    OUTPUT_DIR=$MIUI_ZIP_DIR
fi

DATE=$(date "+%Y-%m-%d %H:%M:%S")
HOSTNAME=$(cat /etc/hostname)

function creatupscrpt() {
    cat > $2 << EOF
$(cat $1 | awk '/getprop/ && /ro.product.device/')
$(cat $1 | awk '/ui_print/ && /Target:/')
show_progress(0.200000, 10);

# Generated by Xiaomi Flashable Firmware Creator
# $DATE - $HOSTNAME

ui_print("Patching firmware images...");
$(cat $1 | awk '/package_extract_file/ && /firmware-update\//')
show_progress(0.100000, 2);
set_progress(1.000000);
EOF

    if grep -wq "/firmware/image/sec.dat" "$2"
    then
        sed -i "s|/firmware/image/sec.dat|/dev/block/bootdevice/by-name/sec|g" "$2"
    elif grep -wq "/firmware/image/splash.img" "$2"
    then
        sed -i "s|/firmware/image/splash.img|/dev/block/bootdevice/by-name/splash|g" "$2"
    fi
}

mkdir /tmp/xiaomi-fw-zip-creator/

echo "Unzipping MIUI.."
mkdir /tmp/xiaomi-fw-zip-creator/unzipped
unzip -q $MIUI_ZIP_DIR/$MIUI_ZIP_NAME 'firmware-update/*' 'META-INF/*' -d /tmp/xiaomi-fw-zip-creator/unzipped/

if [ ! -f /tmp/xiaomi-fw-zip-creator/unzipped/META-INF/com/google/android/update-binary ] || [ ! -f /tmp/xiaomi-fw-zip-creator/unzipped/META-INF/com/google/android/updater-script ] || [ ! -d /tmp/xiaomi-fw-zip-creator/unzipped/firmware-update/ ]; then
    echo "** This zip doesn't contain firmware directory."
    rm -rf /tmp/xiaomi-fw-zip-creator/
    exit 1
fi

mkdir /tmp/xiaomi-fw-zip-creator/out/

mv /tmp/xiaomi-fw-zip-creator/unzipped/firmware-update/ /tmp/xiaomi-fw-zip-creator/out/

mkdir -p /tmp/xiaomi-fw-zip-creator/out/META-INF/com/google/android
mv /tmp/xiaomi-fw-zip-creator/unzipped/META-INF/com/google/android/update-binary /tmp/xiaomi-fw-zip-creator/out/META-INF/com/google/android/

codename=$(cat /tmp/xiaomi-fw-zip-creator/unzipped/META-INF/com/google/android/updater-script | grep -i "xiaomi/" | cut -d / -f2)
echo "Generating updater-script for $codename.."

creatupscrpt /tmp/xiaomi-fw-zip-creator/unzipped/META-INF/com/google/android/updater-script /tmp/xiaomi-fw-zip-creator/out/META-INF/com/google/android/updater-script

echo "Generating changelog.."
device=$(echo $MIUI_ZIP_NAME | cut -d _ -f2)
name=$codename-$device
mkdir /tmp/xiaomi-fw-zip-creator/versioninfo && mkdir /tmp/xiaomi-fw-zip-creator/out/changelog/
sudo mount -o loop /tmp/xiaomi-fw-zip-creator/out/firmware-update/NON-HLOS.bin /tmp/xiaomi-fw-zip-creator/versioninfo && cat /tmp/xiaomi-fw-zip-creator/versioninfo/verinfo/ver_info.txt | tr -d '"\n{}' | tr , '\n' | sed 's/^ *//' | sed 's/         /\n/g' > /tmp/xiaomi-fw-zip-creator/out/changelog/$name.log
sudo umount /tmp/xiaomi-fw-zip-creator/versioninfo
version=$(echo $MIUI_ZIP_NAME | cut -d _ -f3)

LASTLOC=$(pwd)
cd /tmp/xiaomi-fw-zip-creator/out/
echo "Creating firmware zip.. from $MIUI_ZIP_NAME"
zip -q -r9 /tmp/xiaomi-fw-zip-creator/out/fw_$codename"_"$MIUI_ZIP_NAME META-INF/ firmware-update/

cd $LASTLOC
mv /tmp/xiaomi-fw-zip-creator/out/fw_$codename"_"$MIUI_ZIP_NAME $OUTPUT_DIR/
mv /tmp/xiaomi-fw-zip-creator/out/changelog/$name.log $OUTPUT_DIR/changelog/$version/$name.log

rm -rf /tmp/xiaomi-fw-zip-creator/

#Generate diff
oldversion=$(cat miuiversion | head -n2 | tail -n1)
diff $OUTPUT_DIR/changelog/$oldversion/$name.log $OUTPUT_DIR/changelog/$version/$name.log > "$OUTPUT_DIR/changelog/$version/$name.diff"
if [ -f $OUTPUT_DIR/fw_$codename"_"$MIUI_ZIP_NAME ]; then
    echo "All done!"
else
    echo "Failed!"
fi
