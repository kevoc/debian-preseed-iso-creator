#!/usr/bin/env bash

# Logging functions
_error() {
	_log_generic "ERROR" "$@"
}

_warn() {
	_log_generic "WARN" "$@"
}

_info() {
	_log_generic "INFO" "$@"
}

_log_generic() {
	log_level="${1:?}"
	everything_else="${*:2}"

	echo "[$log_level] $everything_else"
}

# Main functions
make_bootable_iso() {
	local src_iso_path="${1:?}"
	local iso_fs_dir="${2:?}"
	local dest_iso_path="${3:?}"

	_info "Creating iso file..."

	cd "$iso_fs_dir" || return

	xorriso -indev "$src_iso_path" \
		-map ./isolinux/ '/isolinux/' \
		-map ./md5sum.txt '/md5sum.txt' \
		-map ./install.amd/initrd.gz '/install.amd/initrd.gz' \
		-boot_image any replay \
		-compliance no_emul_toc \
		-padding included \
		-outdev "$dest_iso_path"
}

regenerate_md5sum() {
	local iso_fs_dir="${1:?}"

	_info "Regenerating md5sum..."

	cd "${iso_fs_dir}" || return
	chmod +w md5sum.txt

	find -follow -type f ! -name md5sum.txt -print0 | xargs -0 md5sum >md5sum.txt

	chmod -w md5sum.txt
}

edit_isolinux_config() {
	local iso_fs_dir="${1:?}"

	_info "Editing isolinux config file..."

	local ISOLINUX_CONFIG_DIR="${iso_fs_dir}/isolinux"
	local ISOLINUX_MAIN_CONFIG_PATH="${ISOLINUX_CONFIG_DIR}/isolinux.cfg"
	local ISOLINUX_MENU_CONFIG_PATH="${ISOLINUX_CONFIG_DIR}/menu.cfg"

	# lower timeout to 1 (value is given as 10ths of a second, so this timeout is very short)
	sed -i -e '/timeout / s/ .*/ 1/' "$ISOLINUX_MAIN_CONFIG_PATH"

	# disable graphical install because preseeding is set up for text-based install
	# and this also makes it default to text-based rather than graphical.
	sed -i '/include gtk.cfg/d' "${ISOLINUX_MENU_CONFIG_PATH}"

	# stop these included files from overriding our timeout. also disables speech synthesis.
	sed -i '/include spkgtk.cfg/d' "${ISOLINUX_MENU_CONFIG_PATH}"
	sed -i '/include spk.cfg/d' "${ISOLINUX_MENU_CONFIG_PATH}"
}

add_preseed() {
	local iso_fs_dir="${1:?}"
	local preseed_file="${2:?}"
	local INSTALL_DIR="install.amd"

	_info "Adding preseed file..."

	cd "${iso_fs_dir}" || return

	chmod +w -R ${INSTALL_DIR}/
	gunzip ${INSTALL_DIR}/initrd.gz

	echo "${preseed_file}" | cpio -H newc -o -A -F ${INSTALL_DIR}/initrd

	gzip ${INSTALL_DIR}/initrd
	chmod -w -R ${INSTALL_DIR}/
}

extract_iso() {
	local src_iso="${1:?}"
	local dest_dir="${2:?}"

	_info "Extracting iso..."

	mkdir -p "${dest_dir}" || return

	xorriso -osirrox on -indev "$src_iso" -extract / "$dest_dir"
}

main() {
	: "${SRC_ISO_PATH:?}"
	: "${DEST_DIR:?}"
	: "${PRESEED_FILE_PATH:?}"

	local tmp_iso_files_dir="${DEST_DIR}/extracted-iso"
	local dest_iso_path="${DEST_DIR}/debian-preseed.iso"

	# Make sure tmp directory doesn't exist yet
	if [ -e "$tmp_iso_files_dir" ]; then
		_error "temp directory already exists"
		return 1
	fi

	# Running these in subshells so any directory changes within functions don't affect eachother
	(extract_iso "$SRC_ISO_PATH" "$tmp_iso_files_dir")

	# from: https://wiki.debian.org/RepackBootableISO#In_xorriso_load_ISO_tree_and_write_modified_new_ISO
	#    Work around a bug in xorriso <= 1.5.6 by preventing /isolinux/isolinux.bin from being 
	#    brought back into the emerging ISO. The file /isolinux/isolinux.bin will then be 
	#    copied correctly from "$orig_iso" to "$new_iso".
	rm "${tmp_iso_files_dir}/isolinux/isolinux.bin"

	(add_preseed "$tmp_iso_files_dir" "$PRESEED_FILE_PATH")
	(edit_isolinux_config "$tmp_iso_files_dir")
	(regenerate_md5sum "${tmp_iso_files_dir}")
	(make_bootable_iso "$SRC_ISO_PATH" "${tmp_iso_files_dir}" "${dest_iso_path}")

	# $tmp_iso_files_dir should now be unecessary, should I just use a temp directory, clean it up after, and not require it as an arg?
}

main "$@"
