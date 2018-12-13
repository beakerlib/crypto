#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /distribution/Library/fips
#   Description: A set of helpers for FIPS 140 testing.
#   Author: Ondrej Moris <omoris@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2018 Red Hat, Inc. All rights reserved.
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
. /usr/bin/rhts-environment.sh || exit 1
. /usr/share/beakerlib/beakerlib.sh || exit 1

rlJournalStart
    rlPhaseStartSetup
        rlRun "rlImport distribution/fips" || rlDie
    rlPhaseEnd

    if ! [ -e /var/tmp/fips-reboot ]; then
        rlPhaseStartTest

            # Check that FIPS 140 mode is supported.
            rlRun "fipsIsSupported" 0,1
            if [ $? -eq 0 ]; then

                # Initially, FIPS mode is disabled.
                rlRun "fipsIsEnabled" 1
                
                # Enable it.
                rlRun "fipsEnable" 0
                
                # Before completing setup by restart, system is misconfigured.
                rlIsRHEL ">6.5" && rlRun "fipsIsEnabled" 2
                
                #rlRun "touch /var/tmp/fips-reboot" 0
                
            rlPhaseEnd

            rhts-reboot
            fi
    else
        rlPhaseStartTest

            # Now, FIPS mode is enabled.
            rlRun "fipsIsEnabled" 0

            rlRun "rm -f /var/tmp/fips-reboot" 0

        rlPhaseEnd
    fi
    
    rlPhaseStartCleanup
    rlPhaseEnd
rlJournalPrintText
rlJournalEnd
