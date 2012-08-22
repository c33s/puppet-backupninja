#!/bin/bash
################################################################################
# lvm_net_backup.sh - Backup lvm snapshot over SSH to files
#
# Copyright (c) 2012 Hyacinthe Cartiaux <Hyacinthe.Cartiaux@uni.lu>
#
# Description : see the print_usage function or launch 'lvm_net_backup.sh --help'
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
################################################################################
#set -x
print_usage()
{
    cat <<EOF

NAME
        lvm_net_backup.sh - Backup lvm snapshot over SSH to files
        Version 0.1

SYNOPSIS
        lvm_net_backup.sh --dest <dest. dir> --ssh <host>
                          --vg <LVM Volume Group> --lv <LVM Logical Volume>
                          [--rotation current|day|month|year|disabled]
                          [--ssh_config <configfile>] [--dry-run] [-f]

DESCRIPTION
        lvm_net_backup.sh is a ssh based backup tool, that saves distant lvm
        snapshot in a local tarball. It implements a simple rotation system.

ARGUMENTS
        --dest <dest. dir>
                Sets the destination directories where the backups is
                placed.

        --ssh <host>
                Hostname of the distant server

        --ssh_port <port>
                Port of the ssh server

        --vg <LVM Volume Group>
                Distant LVM Volume Group on the <host> server

        --lv <LVM Logical Volume>
                Distant LVM Logical Volume on the <host> server, in the
                <LVM Volume Group> VG


OPTIONS
        --rotation <current|day|month|year|disabled>
              /!\ NOT IMPLEMENTED YET /!\
                Specify your rotation time period.
                'current'  only keep the last backup (1)
                'day'      keep the last day, month and year backup (4)
                'month'    keep the last month and last year backup (3)
                'year'     keep the last year backup (2)
                'disabled' keep all the backups

                Default is 'current'

        --dry-run
                Test mode, does nothing, print commands

        -f
                Force, do not ask for confirmation


EXAMPLES
        lvm_net_backup.sh --dest /data --ssh shiva \\
                          --vg vg_shiva_domU --lv hpc-disk \\
                          --rotation day

        When this command is launched, it checks if an action must be done
        (depending on existing backup), and apply the rotation policy (delete
        old backups)
        This will produce a snapshot of host=shiva/vg=vg_shiva_domU/lv=hpc-disk
        in the directory /data on the local host. The file will be written at
        the following paths :  host/vg/lv/year/month/day/host-vg-lv-ymd.tgz
        Additionally, the xen-tools logs and the xen configuration file of the
        domU will be saved in the same directory.

AUTHOR
    Hyacinthe Cartiaux <Hyacinthe.Cartiaux@uni.lu>

REPORTING BUGS
    Please report bugs to <Hyacinthe.Cartiaux@uni.lu>

COPYRIGHT
    This is free software; see the source for copying conditions.  There is
    NO warranty; not even for MERCHANTABILITY or FITNESS FOR A PARTICULAR
    PURPOSE.

EOF
    exit 1
}

exec_cmd() {
  if [ "x$1" == "xDRY_RUN" ] ; then
    shift
    report "[DRY-RUN] $*"
  else
    report "[CMD] $*"
    $* &> /dev/null
    return $?
  fi
}

report() {
  echo "[INFO] $*"
}

ask() {
  echo -n "[INTERACTIVE] $* "
}

error() {
  echo "[ERROR] $*" 1>&2
}

fail() {
  echo "[FAIL] $*" 1>&2
  exit 1
}




######################################
############# PARAMETERS #############
######################################

# Defaults
SSH_PORT=22
ROTATION=current
DRY_RUN=
FORCE=

SERVER_MOUNT_POINT=/mnt/backup

SNAPSHOT_SIZE="1G"

# Parsing
opts=$@
args=($opts)
index=0
for args in $opts
do
  index=`expr $index + 1`
  case $args in
    --dest)       DEST=${args[index]}       ;;
    --ssh)        HOST=${args[index]}       ;;
    --ssh_port)   PORT=${args[index]}       ;;
    --vg)         VG=${args[index]}         ;;
    --lv)         LV=${args[index]}         ;;
    --rotation)   ROTATION=${args[index]}   ;;
    --dry-run)    DRY_RUN="DRY_RUN"         ;;
    -f)           FORCE=-f                  ;;
  esac
done

# variables
ERR=0
err="error "
info="report [INFO] "
fail="err [FAIL] "

YEAR=$(date +%Y)
MONTH=$(date +%m)
DAY=$(date +%d)
DEST_BACKUP_DIR=${DEST}
DEST_BACKUP_FILE=${HOST}_${VG}_${LV}_${YEAR}_${MONTH}_${DAY}.dd.gz

SSH="ssh -p $PORT $HOST -o StrictHostKeyChecking=no"

# Checks
if [ "x$DEST" == "x" ] ; then
  error "--dest parameter undefined"
  ERR=1
fi
if [ "x$HOST" == "x" ] ; then
  error "--ssh parameter undefined"
  ERR=1
fi
if [ "x$VG"   == "x" ] ; then
  error "--vg parameter undefined"
  ERR=1
fi
if [ "x$LV"   == "x" ] ; then
  error "--lv parameter undefined"
  ERR=1
fi

if [ "x$ERR"  == "x1" ] ; then
  print_usage
  fail "Missing parameters, read the manual above !"
fi

# Confirm
report "--dest       = ${DEST}"
report "--ssh        = ${HOST}"
report "--ssh_port   = ${PORT}"
report "--vg         = ${VG}"
report "--lv         = ${LV}"
report "--rotation   = ${ROTATION}"
report "FORCE=${FORCE} DRY_RUN=${DRY_RUN}"


if [ "x$FORCE" != "x-f" ] ; then
  ask "Confirm ? Y/N [N]"
  read confirm

  if [ "x$confirm" != "xY" -a "x$confirm" != "xy"  ] ; then
    report "Exiting now !"
    exit 3
  else
    report "Continue"
  fi
fi


###############################################
############# Pre execution tests #############
###############################################

## dest directory
if [ ! -d "$DEST" ] ; then
  fail "Can't find destination directory ${DEST} !"
fi

## SSH connection
exec_cmd $DRY_RUN $SSH true
if [ "x$?" != "x0" ] ; then
  fail "Connection to ${HOST} failed !"
fi

## VG/LV exists
# test /dev/$VG
exec_cmd $DRY_RUN $SSH "test -e /dev/${VG}"
if [ "x$?" != "x0" ] ; then
  fail "Can't find VG ${VG} on ${HOST} !"
fi
# test /dev/$VG/$LV
exec_cmd $DRY_RUN $SSH "test -e /dev/${VG}/${LV}"
if [ "x$?" != "x0" ] ; then
  fail "Can't find LV ${VG}/${LV} on ${HOST} !"
fi


############################################
############ Snapshot creation #############
############################################

# Create snapshot
exec_cmd $DRY_RUN $SSH "sudo lvcreate -s -L ${SNAPSHOT_SIZE} -n ${LV}-backupsnap /dev/${VG}/${LV}"
if [ "x$?" != "x0" ] ; then
  error "Can't create snapshot ${LV}-backupsnap !"
  ERR=1
fi


################################
############# Save #############
################################

# tar and save locally
if [ "x$ERR"  == "x1" ] ; then
  error "Can't backup !"
elif [ "x$DRY_RUN" == "xDRY_RUN" ] ; then
    report "[DRY-RUN] $SSH sudo dd if=/dev/${VG}/${LV}-backupsnapsnap | gzip > ${DEST_BACKUP_DIR}${DEST_BACKUP_FILE}"
else
    exec_cmd $DRY_RUN mkdir -p $DEST_BACKUP_DIR
    report "[CMD] $SSH sudo dd if=/dev/${VG}/${LV}-backupsnap  | gzip  > ${DEST_BACKUP_DIR}${DEST_BACKUP_FILE}"
                  $SSH "sudo dd if=/dev/${VG}/${LV}-backupsnap | gzip" > ${DEST_BACKUP_DIR}${DEST_BACKUP_FILE}

    if [ "x$?" != "x0" ] ; then
      error "Can't retrieve ${LV}-backupsnap into ${DEST_BACKUP_DIR}${DEST_BACKUP_FILE} !"
      ERR=1
    fi

fi


###################################
############# Clean ! #############
###################################

# Delete snapshot
exec_cmd $DRY_RUN $SSH "sudo lvremove -f /dev/${VG}/${LV}-backupsnap"
if [ "x$?" != "x0" ] ; then
  fail "Can't remove snapshot ${LV}-backupsnap !"
  ERR=1
fi


#########################################
############# Rotation work #############
#########################################

#
# NOT
#     IMPLEMENTED
#                 YET
#

exit $ERR

