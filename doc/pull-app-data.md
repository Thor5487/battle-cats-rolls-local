
# Pull app data on non-rooted device

The steps are as followings:

* Modify the app to allow backing up
* Enter the game to download app data
* Backup the app data to computer
* Extract the backup
* Profit

## Disassemble the APK

``` shell
apktool d data/jp/10.0.0/bc-jp.apk
```

## Modify the app to allow backing up

Idea is based on [How to enable adb backup for any app changing android:allowBackup](
https://forum.xda-developers.com/android/software-hacking/guide-how-to-enable-adb-backup-app-t3495117)

Edit `AndroidManifest.xml` and change `android:allowBackup` to be `"true"`.

## Rebuild the app

Commands are based on [Decompile and Recompile An android APK using Apktool](
https://medium.com/@sandeepcirusanagunla/decompile-and-recompile-an-android-apk-using-apktool-3d84c2055a82)

``` shell
# Rebuild the app
apktool b bc-jp

# Generate signing key (or use an existing key)
keytool -genkey -v -keystore my-release-key.keystore -alias alias_name -keyalg RSA -keysize 2048 -validity 10000

# Sign it with the key
jarsigner -verbose -sigalg SHA1withRSA -digestalg SHA1 -keystore my-release-key.keystore bc-jp/dist/bc-jp.apk alias_name

# Verify it
jarsigner -verify -verbose -certs bc-jp/dist/bc-jp.apk
```

There's no need to use `zipalign` because we don't need to optimize it,
signing alone can let us install it already.

## Send the APK to the device

We send to `Download` directory (or whatever you prefer):

``` shell
adb push bc-jp/dist/bc-jp.apk /sdcard/Download
```

And install the APK from there, running it, let it downloads data from server.

## Pull app data via backing up

Now since the app allows backing up, we can grab the app data:

``` shell
adb backup -apk jp.co.ponos.battlecats
```

## Extract app data from backup

The default backup file is called `backup.ab`, and it's a tarball compressed
in DEFLATE with its own header. In order to extract it, we use `dd` to skip
the header and pipe to a program which can decompress in DEFLATE.

This is documented in [Backup android app, data included, no root needed, with adb](
https://gist.github.com/AnatomicJC/e773dd55ae60ab0b2d6dd2351eb977c1)

I couldn't install `qpdf` and `openssl zlib` didn't work for me, so I found
`pigz` which I can use to decompress in DEFLATE.

```
# Make sure we don't mess with the directory
mkdir tmp
mv backup.ab tmp
cd tmp/

# Extract app data from the backup
dd if=backup.ab bs=24 skip=1 | pigz -d -z -c | tar xf -
```
