#!/bin/bash

BASEDIR=$(dirname "$(readlink -f "$0")")
BINDIR="$BASEDIR/bin"
BUILDDIR="$BASEDIR/build"
ASSETDIR="$BASEDIR/asset"
LISTDIR="$BASEDIR/list"
TMPDIR="$BASEDIR/tmp"
ERRORCOLOR=31
WARNCOLOR=36
INFOCOLOR=32
HEADCOLOR=35
R="{}" # Color Reset Mark

color_start() {
	if [[ ! -z $2 ]]; then
		echo -n "\\\\033\\[$1m"
	else
		echo -n "\033[$1m"
	fi
}

color_end() {
	echo -n "\033[0m"
}

color() {
	echo -n "$(color_start "$1")$2$(color_end)"
}

bold() {
	echo -n "$(color 1 "$1")$R"
}

puts() {
	local NEWLINE=
	if [[ ! -z "$2" ]]; then
		NEWLINE=-n
	fi
	echo -e $NEWLINE "$1"
}

error() {
	puts "$(color $HEADCOLOR "[ERROR]")   $(echo -n "$(color $ERRORCOLOR "$1")" | sed "s/$R/$(color_start $ERRORCOLOR 1)/")" 1>&2
	cleanup
	exit 1
}

warn() {
	puts "$(color $HEADCOLOR "[WARNING]") $(echo -n "$(color $WARNCOLOR "$1")" | sed "s/$R/$(color_start $WARNCOLOR 1)/")" $2
}

info() {
	puts "$(color $HEADCOLOR "[INFO]")    $(echo -n "$(color $INFOCOLOR "$1")" | sed "s/$R/$(color_start $INFOCOLOR 1)/")" $2
}

info_done() {
	puts " $(color $INFOCOLOR "Done.")"
}

delete() {
	local FILE
	local BASENAME
	for FILE in $BUILDDIR/$1; do
		BASENAME="${FILE#$BUILDDIR/}"
		if [[ ! -w "$FILE" ]]; then
			warn "Cannot find file $(bold "$BASENAME") to delete."
		else
			rm -rf "$FILE" || error "Failed to delete $(bold "$BASENAME")."
			info "Deleted $(bold "$BASENAME")."
		fi
	done
}

copy() {
	local FILE
	local BASENAME
	local ASSET
	local DIR
	for FILE in $BUILDDIR/$1; do
		BASENAME="${FILE#$BUILDDIR/}"
		if [[ -w "$FILE" ]]; then
			warn "File $(bold "$BASENAME") already exists. Will be replaced."
		fi
		ASSET="$ASSETDIR/$BASENAME"
		if [[ ! -r "$ASSET" ]]; then
			error "Cannot find asset $(bold "$BASENAME")."
		fi
		DIR="$(dirname "$FILE")"
		mkdir -p "$DIR" && cp -rf "$ASSET" "$DIR" || error "Failed to copy $(bold "$BASENAME")."
		info "Copied $(bold "$BASENAME")."
	done
}

apk_res() {
	local FILE="$BUILDDIR/$1"
	local RESDIR="$ASSETDIR/$1"
	local TMP="$TMPDIR/$1"
	if [[ ! -f "$FILE" || ! -r "$FILE" ]]; then
		error "Cannot find apk $(bold "$1" "$ERRORCOLOR")."
	fi
	mkdir -p "$TMP"
	# unpack
	info "Unpacking apk $(bold "$1")..." 1
	unzip -qq "$FILE" -d "$TMP"
	if [[ $? -gt 0 ]]; then
		error "Cannot unpack $(bold "$1")."
	fi
	info_done
	# copy stuff
	if [[ ! -d "$RESDIR" ]]; then
		error "Cannot find resource for $(bold "$1")."
	fi
	info "Replacing resources..." 1
	cp -rf "$RESDIR/." "$TMP"
	info_done
	# pack
	info "Packing apk $(bold "$1")..." 1
	pushd "$TMP" > /dev/null
	zip -rqX "$TMP.zip" .
	popd > /dev/null
	info_done
	info "Zipaligning new apk..." 1
	$BINDIR/zipalign -f 4 "$TMP.zip" "$FILE"
	info_done
	rm -rf "$TMP.zip" "$TMP"
}

cleanup() {
	info "Cleaning up..." 1
	rm -rf "$TMPDIR"
	if [[ ! -z "$1" ]]; then
		rm -rf "$BUILDDIR"
	fi
	info_done
}

ZIPNAME=${1:?"Usage: $0 rom.zip"}
ZIPNAME=${ZIPNAME##*/}
ZIPNAME=${ZIPNAME%.zip}

if [[ ! -f "$1" || ! -r "$1" ]]; then
	error "Can't read file $(bold "$1")!"
fi

# create TMPDIR
mkdir -p "$TMPDIR"
# create BUILDDIR
rm -rf "$BUILDDIR"
mkdir -p "$BUILDDIR"

# unzip to BUILDDIR
info "Unzipping $(bold "$1")..." 1
unzip -qq "$1" -d "$BUILDDIR"
if [[ $? -gt 0 ]]; then
	echo
	error "Failed to unzip ROM!"
fi
info_done

# delete files
while read -r LINE; do
	delete "$LINE"
done < "$LISTDIR/delete"

# copy files
while read -r LINE; do
	copy "$LINE"
done < "$LISTDIR/copy"

# other stuff
apk_res "aroma/circlebattery/app/SystemUI.apk"
sed -i "/set_perm.\+\/xbin\/su/a set_perm(0, 0, 0777, \"/system/bin/.ext\");\nset_perm(0, 0, 06755, \"/system/bin/.ext/.su\")" "$BUILDDIR/META-INF/com/google/android/updater-script"

info "Tweaking $(bold "build.prop")..." 1
sed -i '/ro\.ril\.hsxpa/s/1/2/;/ro\.ril\.gprsclass/s/10/12/' "$BUILDDIR/system/build.prop"
info_done

# zip everything back together
info "Building final zip file..." 1
pushd "$BUILDDIR" > /dev/null
zip -9rqX "$BASEDIR/$ZIPNAME.cooked.zip" .
popd > /dev/null
info_done

cleanup 1

info "Saved as $(bold "$ZIPNAME.cooked.zip")."
