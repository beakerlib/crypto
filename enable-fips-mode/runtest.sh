#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /enable-fips-mode
#   Description: Enable FIPS 140 mode.
#   Author: Ondrej Moris <omoris@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2023 Red Hat, Inc. All rights reserved.
#
#   This copyrighted material is made available to anyone wishing
#   to use, modify, copy, or redistribute it subject to the terms
#   and conditions of the GNU General Public License version 2.
#
#   This program is distributed in the hope that it will be
#   useful, but WITHOUT ANY WARRANTY; without even the implied
#   warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#   PURPOSE. See the GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public
#   License along with this program; if not, write to the Free
#   Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
#   Boston, MA 02110-1301, USA.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Include Beaker environment
. /usr/share/beakerlib/beakerlib.sh

rlJournalStart

    rlPhaseStartSetup
        rlRun "rlImport /crypto/fips" || rlDie
    
        if [ "$TMT_REBOOT_COUNT" -eq 0 ]; then
            if ! fipsIsSupported; then
                rlFail "FIPS 140 mode is not supported on this machine!"
                rlPhaseEnd
                rlJournalPrintText                
                rlJournalEnd
                exit 0
            fi

            if fipsIsEnabled; then
                rlPass "FIPS 140 mode is already enabled!"
                rlPhaseEnd
                rlJournalPrintText                
                rlJournalEnd
                exit 0
            fi
            
            rlRun "fipsEnable"
            
            # Umount common mountpoints to prevent mount locking.
            rlCheckMountQa && rlRun "umount -l /mnt/qa"
            rlCheckMountRedhat && rlRun "umount -l /mnt/redhat"
            rlCheckMountEngarchive && rlRun "umount -l /mnt/engarchive /mnt/engarchive2"

            rlPhaseEnd
            tmt-reboot
        else
            rlRun "fipsIsEnabled"
        fi
    rlPhaseEnd

rlJournalPrintText

rlJournalEnd
