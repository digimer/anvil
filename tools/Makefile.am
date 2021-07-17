MAINTAINERCLEANFILES	= Makefile.in

# XXX recheck after rebase!
EXTRA_DIST		= \
			  watch_drbd

dist_sbin_SCRIPTS	= \
			  anvil-boot-server \
			  anvil-change-password \
			  anvil-check-memory \
			  anvil-configure-host \
			  anvil-cycle-vm-nics \
			  anvil-daemon \
			  anvil-delete-server \
			  anvil-download-file \
			  anvil-file-details \
			  anvil-join-anvil \
			  anvil-maintenance-mode \
			  anvil-manage-files \
			  anvil-manage-firewall \
			  anvil-manage-keys \
			  anvil-manage-power \
			  anvil-manage-server \
			  anvil-migrate-server \
			  anvil-parse-fence-agents \
			  anvil-provision-server \
			  anvil-rename-server \
			  anvil-safe-start \
			  anvil-scan-network \
			  anvil-shutdown-server \
			  anvil-sync-shared \
			  anvil-update-issue \
			  anvil-update-states \
			  anvil-update-system \
			  anvil-watch-bonds \
			  scancore \
			  striker-boot-machine \
			  striker-get-peer-data \
			  striker-initialize-host \
			  striker-manage-install-target \
			  striker-manage-peers \
			  striker-manage-vnc-pipes \
			  striker-open-ssh-tunnel \
			  striker-parse-os-list \
			  striker-parse-oui \
			  striker-prep-database \
			  striker-purge-target \
			  striker-scan-network \
			  striker-show-db-counts \
			  striker-auto-initialize-all

fencedir		= $(FASEXECPREFIX)/sbin

dist_fence_SCRIPTS	= \
			  fence_delay \
			  fence_pacemaker

sharedir		= ${datarootdir}/anvil

dist_share_DATA		= striker-auto-initialize-all.example
