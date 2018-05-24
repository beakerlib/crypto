#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   lib.sh of /distribution/Library/fips
#   Description: A set of helpers for FIPS related testing.
#   Author: Ondrej Moris <omoris@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2012 Red Hat, Inc. All rights reserved.
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
#   library-prefix = fips
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

true <<'=cut'
=pod

=head1 NAME

distribution/fips - a set of helpers for FIPS related testing

=head1 DESCRIPTION

This is a library intended for FIPS related testing. Currently it contains
just a single function checking FIPS status. The library is intended to be
extended.

=cut

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#   Variables
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

true <<'=cut'
=pod

=head1 GLOBAL VARIABLES

=over

=item fipsBOOTDEV

Boot device.

=item fipsBOOTCONFIG

Location of bootloader configuration file.

=back

=cut

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#   Functions
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

true <<'=cut'
=pod

=head1 FUNCTIONS

=head2 fipsIsEnabled

Function check current state of FIPS mode. Returns 0 if it is correctly 
enabled, 1 if disabled and 2 otherwise (misconfiguration).

=over

=back

=cut

function fipsIsEnabled {
    rlLog "Checking FIPS mode status"
    if rlIsRHEL '>6.5'; then
        if [[ -n $OPENSSL_ENFORCE_MODULUS_BITS ]]; then
            rlLog "OpenSSL working in new FIPS mode, 1024 bit RSA disallowed!"
        else
            rlLog "OpenSSL working in compatibility FIPS mode, 1024 bit allowed"
        fi
    fi
    if grep -q 1 /proc/sys/crypto/fips_enabled; then
        if rlIsRHEL 4 5 || rlIsRHEL '<6.5'; then
            rlLog "FIPS mode is enabled"
            return 0
        else
            if [ -e /etc/system-fips ]; then
                rlLog "FIPS mode is enabled"
                return 0
            else
                rlLog "FIPS mode is misconfigured"
                rlLog "  (kernel flag fips=1 set, but /etc/system-fips is missing)"
                return 2
            fi
        fi
    else
        if [ -e /etc/system-fips ]; then
            rlLog "FIPS mode is misconfigured"
            rlLog "  (kernel flag fips=0 set, but /etc/system-fips is present)"
            return 2
        else
            rlLog "FIPS mode is disabled"
            return 1
        fi
    fi
    return 2
}

true <<'=cut'
=pod

=head2 fipsIsSupported

Function verifies whether the FIPS 140 product is supported on the current platform.
Returns 0 if FIPS mode is supported, 1 if not.

=over

=back

=cut

function fipsIsSupported {

    local ARCH=`uname -i`
    local VER=`cat /etc/redhat-release | sed -n 's/.*\([0-9]\.[0-9]*\).*/\1/p'`
    local KERNEL=`uname -r | cut -d '.' -f 1`
    local ALT=0
    local PASS=0

    rlPhaseStartSetup "Checking FIPS support"

        if [ `rlGetDistroRelease` -eq "7" ] && [ "$KERNEL" -eq "4" ]; then
            rlLog "Product: RHEL-ALT-$VER"
            PASS=1
        else
            rlLog "Product: RHEL-$VER"
        fi

        rlLog "Architecture: $ARCH"

        # FIPS is not allowed on s390x on RHEL <7.1.
        if [[ $ARCH =~ s390 ]] && rlIsRHEL '<7.1'; then
            PASS=1
        fi

        # FIPS is not allowed on AArch64.
        if [[ $ARCH =~ aarch ]]; then
            PASS=1
        fi

        if [ "$PASS" -eq "1" ]; then
            rlLog "FIPS mode is not supported"
            rlLog "See https://wiki.test.redhat.com/BaseOs/Security/FIPS#SupportedPlatforms"
            return 1
        fi

        rlLog "FIPS mode is supported"
        return 0

    rlPhaseEnd
}

true <<'=cut'
=pod

=head2 fipsEnable

Function enables FIPS 140 product, please notice that the process includes 
inevitable restart of the machine. Returns 0 if FIPS mode was correctly enabled,
1 if not and 2 in case that any error was encountered.

=over

=back

=cut

function fipsEnable {

    local ARCH=`uname -i`

    rlPhaseStartSetup "Enable FIPS mode"
    
    # FIPS requires SSE2 instruction set for OpenSSL.
    if  echo $ARCH | grep "i[36]86" && ! grep "sse2" /proc/cpuinfo; then
        rlLogError "FIPS requires SSE2 instruction set for OpenSSL";
        return 1
    fi
    
    # FIPS must be supported before its enabling.
    if ! rlRun "fipsIsSupported"; then
        return 1
    fi

    # Verify the FIPS state.
    if grep "1" "/proc/sys/crypto/fips_enabled"; then
        if rlIsRHEL ">=6" && !rlCheckRpm "dracut-fips"; then
            continue;
        fi
        rlLog "FIPS is already enabled!"
    fi
    
    # Backup a message of the day.
    rlRun "cp -f /etc/motd /var/tmp/motd.backup" 0
    
    # Turn-off prelink (if prelink is installed).
    if rlCheckRpm "prelink"; then
        # sometimes prelink complains about files being changed during
        # unlinking so let's run a simple yum command to make sure yum
        # is not running in the background ("somehow") and wait for it
        # to finish (yum automatically uses lockfiles for that)
        if ! rlIsRHEL '<5'; then
            rlRun "yum list --showduplicates prelink"
        fi
        
        # make sure prelink job is not running now (e.g. started by cron)
        rlRun "killall prelink" 0,1
        rlRun "sed -i 's/PRELINKING=.*/PRELINKING=no/g' /etc/sysconfig/prelink" 0
        rlRun "sync" 0 "Commit change to disk"
        rlRun "killall prelink" 0,1
        rlRun "prelink -u -a" 0
    fi
    
    # Enforce 2048 bit limit on RSA and DSA generation (RHBZ#1039105)
    if ! rlIsRHEL '<6.5' 5 4; then
        if ! grep 'OPENSSL_ENFORCE_MODULUS_BITS' /etc/environment; then
            rlRun "echo 'OPENSSL_ENFORCE_MODULUS_BITS=true' >> /etc/environment"
        fi
        rlRun "echo 'export OPENSSL_ENFORCE_MODULUS_BITS=true' > /etc/profile.d/openssl.sh"
        rlRun "chmod +x /etc/profile.d/openssl.sh"
        rlRun "echo 'setenv OPENSSL_ENFORCE_MODULUS_BITS true' > /etc/profile.d/openssl.csh"
        rlRun "chmod +x /etc/profile.d/openssl.csh"
        # beaker tests don't use profile or environment so we have to set
        # their environment separately
        BEAKERLIB=${BEAKERLIB:-"/usr/share/beakerlib"}
        rlRun "mkdir -p '${BEAKERLIB}/plugins/'" 0-255
        rlRun "echo 'export OPENSSL_ENFORCE_MODULUS_BITS=true' > '${BEAKERLIB}/plugins/openssl-fips-override.sh'"
        rlRun "chmod +x '${BEAKERLIB}/plugins/openssl-fips-override.sh'"
    fi
    
    if ! rlIsRHEL 5; then
        
        # Install dracut and dracut-fips on RHEL7 and RHEL6
        rlCheckRpm "dracut" || rlRun "yum --enablerepo='*' install dracut -y" 0
        rlCheckRpm "dracut-fips" || rlRun "yum --enablerepo='*' install dracut-fips -y" 0
        if grep -sE '\<aes\>' /proc/cpuinfo && grep -sE '\<GenuineIntel\>' /proc/cpuinfo; then
            rlLogInfo "AES instruction set on Intel CPU detected"
            rlCheckRpm "dracut-fips-aesni" || \
                rlRun "yum --enablerepo='*' install -y dracut-fips-aesni" 0 \
                "Installing dracut-fips-aesni"
                
        else
            rlLogInfo "CPU is a non-Intel or lacking AES instruction set"
            rlCheckRpm "dracut-fips-aesni" && \
                rlRun "yum remove -y dracut-fips-aesni" 0 "Removing dracut-fips-aesni"
        fi

        # Re-generate initramfs to include FIPS integrity checks.
        rlLogInfo "Regenerating initramfs"
        rlRun "dracut -v -f" 0
    fi
    
    
    return 2
}


function _modifyBootLoader {

    local ARCH=`uname -i`

    # Fine-tune SED options
    if rlIsRHEL 5; then
        SED_OPTIONS='-c'
    else
        SED_OPTIONS='--follow-symlinks'
    fi
    
    # Remove any FIPS-related kernel parameters first
    sed -i $SED_OPTIONS 's/ fips=[01] boot=$fipsBOOTDEV/ /g' $fipsBOOTCONF
    sed -i $SED_OPTIONS 's/ fips=[01] boot=$fipsBOOTDEV/ /g' $fipsBOOTCONF

    case $ARCH in
        i386|x86_64)
            if rlCheckRpm "grub2" || rlCheckRpm "grub2-efi"; then
                rlRun "sed -i $SED_OPTIONS 's|\(vmlinuz.*\)|\1 fips=1 boot=$BOOT_DEV|g' $BOOTCONF"
            else
                rlRun "sed -i $SED_OPTIONS 's|\(kernel.*\)|\1 fips=1 boot=$BOOT_DEV|g' $BOOTCONF" 0
            fi
            ;;
        ia64)
            if grep -q 'append' $BOOTCONF; then
                rlRun "sed -i $SED_OPTIONS 's|\(append=.*\)\"|\1 fips=1 boot=$BOOT_DEV\"|g' $BOOTCONF" 0
            else
                rlRun "sed -i $SED_OPTIONS 's|\(initrd.*\)|\1\n\tappend=\"fips=1 boot=$BOOT_DEV\"|g' $BOOTCONF" 0
            fi
            ;;
        ppc|ppc64|ppc64le)
            if rlCheckRpm "grub2" || rlCheckRpm "grub2-efi"; then
                rlRun "sed -i $SED_OPTIONS 's|\(vmlinuz.*\)|\1 fips=1 boot=$BOOT_DEV|g' $BOOTCONF"
            else
                if grep -q 'append' $BOOTCONF; then
                    rlRun "sed -i $SED_OPTIONS 's|\(append=.*\)\"|\1 fips=1 boot=$BOOT_DEV\"|g' $BOOTCONF" 0
                else
                    rlRun "sed -i $SED_OPTIONS 's|\(root=.*\)|\1 append=\"\"|g' $BOOTCONF"
                fi
            fi
            ;;
        s390x)
            rlRun "sed -i $SED_OPTIONS 's/parameters=\"\(.*\)\"/parameters=\"\1 fips=1 boot=$BOOT_DEV\"/g' $BOOTCONF" 0
	    rlRun "zipl" 0
            ;;
        
    esac	    
}

function fipsSetState {
    
    local new_state=$1

    case "$new_state" in
        0)
           ;; 
        *)
            rlLogError "Unexpected state (\"$new_state\" given, 0-3 expected)"
    esac
    
    return 2
}

true <<'=cut'
=pod

=head2 fipsDisable

Function disables FIPS 140 product, please notice that the process includes 
inevitable restart of the machine. Returns 0 if FIPS mode was correctly disabled,
1 if not and 2 in case that any error was encountered.

=over

=back

=cut

function fipsDisable {
    return 2
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#   Initialization & Verification 
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   This is an initialization and verification callback which will be 
#   called by rlImport after sourcing the library. The function
#   returns 0 only when the library is ready to serve.

fipsLibraryLoaded() {

    fipsBOOTDEV=`df -P /boot/ | tail -1 | awk '{print $1}'`
    if [ -z "$fipsBOOTDEV" ]; then
        rlLogError "Unable to detect /boot device name!"

        # debug
        df /boot/

        return 1
    fi

    if [[ "${USE_UUID:-yes}" != "no" && "${USE_UUID:-1}" != "0" ]]; then
        
        UUID=$(blkid -s UUID -o value $fipsBOOTDEV)
        if [ -z "$UUID" ]; then
            rlLogError "Unable to detect boot device UUID!"
                
            # debug
            df /boot
            blkid -s UUID -o value $fipsBOOTDEV
            
            return 1
        fi
        
        fipsBOOTDEV="UUID=$UUID"               
    fi
    
    fipsBOOTCONFIG="/boot/grub2/grub.cfg"
    case "$(uname -i)" in
        i386|x86_64)
            rlCheckRpm "grub2" || fipsBOOTCONFIG="/boot/grub/grub.conf"
            ;;
        ia64)
            fipsBOOTCONFIG="/etc/elilo.conf"
            ;;
        ppc|ppc64)
            rlCheckRpm "grub2" || fipsBOOTCONFIG="/boot/etc/yaboot.conf"
            ;;
    esac            
    rlLog "Setting fipsBOOTCONFIG=$fipsBOOTCONFIG"

    return 0
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#   Authors
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

true <<'=cut'
=pod

=head1 AUTHORS

=over

=item *

Ondrej Moris <omoris@redhat.com>

=back

=cut

