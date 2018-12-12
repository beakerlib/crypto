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

    local arch=$(uname -i)
    local rhel=$(cat /etc/redhat-release | sed -n 's/.*\([0-9]\.[0-9]*\).*/\1/p')
    local kernel=$(uname -r)
    local supported=1

    # Check RHEL version.
    if [[ $rhel =~ 7\. ]] && [[ $kernel =~ 4\. ]]; then
        rlLog "Product: RHEL-ALT-7"
        rlLog "FIPS 140 is not supported in RHEL-ALT-7!" 
        supported=0
    else
        rlLog "Product: RHEL-${rhel}"
    fi

    # Check HW architecture.
    rlLog "Architecture: $arch"
    if [[ $arch =~ i[36]86 ]] && ! grep -q "sse2" /proc/cpuinfo; then
        rlLog "FIPS 140 requires SSE2 instruction set for OpenSSL on Intel!"
        supported=0
    elif [[ $arch =~ s390 ]] && rlIsRHEL '<7.1'; then
        rlLog "FIPS 140 is not supported on s390x in RHEL older than 7.1!"
        supported=0
    elif [[ $ARCH =~ aarch ]] && ! rlIsRHEL '8'; then
        rlLog "FIPS 140 is not supported on aarch64 in RHEL older than 8.0!"
        supported=0
    fi

    # Report,
    if [ "$supported" == "0" ]; then
        rlLog "FIPS 140 mode is not supported"
        rlLog "See https://wiki.test.redhat.com/BaseOs/Security/FIPS#SupportedPlatforms"
        return 1
    fi
    rlLog "FIPS 140 mode is supported"
    return 0
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

    # Check if FIPS 140 mode is supported on a machine.
    rlRun "fipsIsSupported" || return 1
    
    # Check if FIPS 140 mode is enabled already.
    if fipsIsEnabled; then
        rlLog "FIPS 140 mode is already enabled!"
        return 0
    fi
    
    # Turn-off prelink (if prelink is installed).
    _disablePrelink || return 1

    # Enforce 2048 bit limit on RSA and DSA generation (RHBZ#1039105).
    _enforceModulusBits || return 1
   
    # Enable FIPS 140 mode.
    _enableFIPS || return 1

    # Modify bootloader.
    _modifyBootloader || return 1
    
    # Success.
    return 0
}

function _disablePrelink {
    if rlCheckRpm "prelink"; then

        # Sometimes prelink complains about files being changed during
        # unlinking so let's run a simple yum command to make sure yum
        # is not running in the background ("somehow") and wait for it
        # to finish (yum automatically uses lockfiles for that).
        if ! rlIsRHEL '<5'; then
            rlRun "yum list --showduplicates prelink" 0 "Wait for yum"
        fi
        
        # Make sure prelink job is not running now (e.g. started by cron).
        rlRun "kill $(pgrep prelink)" 0,1 "Kill all prelinks"
        rlRun "sed -i 's/PRELINKING=.*/PRELINKING=no/g' /etc/sysconfig/prelink" 0 "Configure system not to use prelink"
        rlRun "sync" 0 "Commit change to disk"
        rlRun "kill $(pgrep prelink)" 0,1 "Kill all prelinks (again)"
        rlRun "prelink -u -a" 0 "Un-prelink the system"
    fi

    return 0
}

function _enforceModulusBits {
    if ! rlIsRHEL '<6.5' 5 4; then
        if ! grep 'OPENSSL_ENFORCE_MODULUS_BITS' /etc/environment; then
            rlRun "echo 'OPENSSL_ENFORCE_MODULUS_BITS=true' >> /etc/environment" 0 "Enable OPENSSL_ENFORCE_MODULUS_BITS (env)"
        fi
        rlRun "echo 'export OPENSSL_ENFORCE_MODULUS_BITS=true' > /etc/profile.d/openssl.sh && \
               chmod +x /etc/profile.d/openssl.sh && \
               echo 'setenv OPENSSL_ENFORCE_MODULUS_BITS true' > /etc/profile.d/openssl.csh && \
               chmod +x /etc/profile.d/openssl.csh" 0 "Enable OPENSSL_ENFORCE_MODULUS_BITS (profiles)"
        
        # Beaker tests don't use profile or environment so we have to set
        # their environment separately.
        BEAKERLIB=${BEAKERLIB:-"/usr/share/beakerlib"}
        rlRun "mkdir -p ${BEAKERLIB}/plugins/ && \
               echo 'export OPENSSL_ENFORCE_MODULUS_BITS=true' > ${BEAKERLIB}/plugins/openssl-fips-override.sh && \
               chmod +x ${BEAKERLIB}/plugins/openssl-fips-override.sh" 0 "Enable OPENSSL_ENFORCE_MODULUS_BITS (beaker)"
    fi

    return 0
}

function _enableFIPS {

    if rlIsRHEL ">=8"; then
        
        # Use crypto-policies to set-up FIPS 140 mode.
        rlRun "fips-mode-setup --enable" 0 "Enable FIPS 140 mode"
       
    elif rlIsRHEL ">=6"; then
    
        # Install dracut and dracut-fips on RHEL7 and RHEL6.
        rlCheckRpm "dracut" || rlRun "yum --enablerepo='*' install dracut -y" 0 "Install dracut"
        rlCheckRpm "dracut-fips" || rlRun "yum --enablerepo='*' install dracut-fips -y" 0 "Install dracut-fips"

        if grep -qE '\<aes\>' /proc/cpuinfo && \
           grep -qE '\<GenuineIntel\>' /proc/cpuinfo; then

            rlLogInfo "AES instruction set on Intel CPU detected"

            if [ "$IGNORE_AESNI" == "1" ]; then
                rlLogInfo "Installation of dracut-fips-aesni skipped"
            else
                rlCheckRpm "dracut-fips-aesni" || \
                    rlRun "yum --enablerepo='*' install -y dracut-fips-aesni" 0 "Install dracut-fips-aesni"
            fi
        else
            rlLogInfo "Intel AES instruction set not detected"
            rlCheckRpm "dracut-fips-aesni" && rlRun "yum remove -y dracut-fips-aesni" 0 "Remove dracut-fips-aesni"
        fi
          
        # Re-generate initramfs to include FIPS dracut modules.
        rlRun "dracut -v -f" 0 "Regenerate initramfs"
    fi

    return 0
}

function _modifyBootloader {

    # On RHEL-8, fips-mode-setup binary modifies bootloader.
    rlIsRHEL "<8" && return 0

    local arch=$(uname -i)
    local sed_options="--follow-symlinks"

    rlIsRHEL 5 && sed_options="-c"
    
    # Get block device name.
    local boot_dev=$(df -P /boot/ | tail -1 | awk '{print $1}')
    if [ -z "$boot_dev" ]; then
        rlFail "Can't detect /boot device name, cannot continue!"
        rlLog "df /boot/ | tail -1" 
        return 1
    fi
    
    if [[ "${USE_UUID:-yes}" != "no" && "${USE_UUID:-1}" != "0" ]]; then

        # Get block device UUID, see BZ 1014527 if UUIDs don't work.
        local old_boot_dev=$boot_dev
        boot_dev="UUID=$(blkid -s UUID -o value $old_boot_dev)"
        if [ "$boot_dev" == "UUID=" ]; then
            rlFail "Cannnot detect /boot device UUID, cannot continue!"
            rlLog "blkid -s UUID -o value $old_boot_dev" 
            return 1
        fi
    fi

    local bootconf=""
    case $arch in
        i386|x86_64)

            # Since RHEL-7.4-20170421.1, grub2-efi packages were renamed
            # to grub2-efi-ia32 and grub2-efi-x64
            if rpm -qa | grep "grub2-efi"; then
                bootconf="/boot/efi/EFI/redhat/grub.cfg"
                rlRun "sed -i $sed_options 's/ fips=[01] boot=$boot_dev/ /g' $bootconf" 0 \
                    "Reset GRUB fips configuration"
                rlRun "sed -i $sed_options 's|\(vmlinuz.*\)|\1 fips=1 boot=$boot_dev|g' $bootconf" 0 \
                    "Setup GRUB fips configuration"
            elif rpm -qa | grep "grub2"; then
                bootconf="/boot/grub2/grub.cfg"
                rlRun "sed -i $sed_options 's/ fips=[01] boot=$boot_dev/ /g' $bootconf" 0 \
                    "Reset GRUB fips configuration"
                rlRun "sed -i $sed_options 's|\(vmlinuz.*\)|\1 fips=1 boot=$boot_dev|g' $bootconf" \
                    "Setup GRUB fips configuration"
            elif mount | grep -i efi; then
                bootconf="/boot/efi/EFI/redhat/grub.conf"
                rlRun "sed -i $sed_options 's/ fips=[01] boot=$boot_dev/ /g' $bootconf" 0 \
                    "Reset GRUB fips configuration"
                rlRun "sed -i $sed_options 's|\(vmlinuz.*\)|\1 fips=1 boot=$boot_dev|g' $bootconf" \
                    "Setup GRUB fips configuration"
            else
                bootconf="/boot/grub/grub.conf"
                rlRun "sed -i $sed_options 's/ fips=[01] boot=$boot_dev/ /g' $bootconf" 0 \
                    "Reset GRUB fips configuration"
                rlRun "sed -i $sed_options 's|\(kernel.*\)|\1 fips=1 boot=$boot_dev|g' $bootconf" 0 \
                    "Setup GRUB fips configuration"
            fi
            ;;
        ia64)
            bootconf="/etc/elilo.conf"
            rlRun "sed -i $sed_options 's/fips=[01] boot=$boot_dev/ /g' $bootconf" 0
            if grep -q 'append' $bootconf; then
                rlRun "sed -i $sed_options 's|\(append=.*\)\"|\1 fips=1 boot=$boot_dev\"|g' $bootconf" 0
            else
                rlRun "sed -i $sed_options 's|\(initrd.*\)|\1\n\tappend=\"fips=1 boot=$boot_dev\"|g' $bootconf" 0
            fi
            ;;
        ppc|ppc64|ppc64le)
            if rpm -qa | grep "grub2-efi"; then
                bootconf="/boot/efi/EFI/redhat/grub.cfg"
                rlRun "sed -i $sed_options 's/ fips=[01] boot=$boot_dev/ /g' $bootconf" 0
                rlRun "sed -i $sed_options 's|\(vmlinuz.*\)|\1 fips=1 boot=$boot_dev|g' $bootconf"
            elif rpm -qa | grep "grub2"; then
                bootconf="/boot/grub2/grub.cfg"
                rlRun "sed -i $sed_options 's/ fips=[01] boot=$boot_dev/ /g' $bootconf" 0
                rlRun "sed -i $sed_options 's|\(vmlinuz.*\)|\1 fips=1 boot=$boot_dev|g' $bootconf"
            else
                bootconf="/etc/yaboot.conf"
                grep -q 'append' $bootconf || \
                    rlRun "sed -i $sed_options 's|\(root=.*\)|\1 append=\"\"|g' $bootconf"
                rlRun "sed -i $sed_options 's/fips=[01] boot=$boot_dev/ /g' $bootconf" 0
                rlRun "sed -i $sed_options 's|\(append=.*\)\"|\1 fips=1 boot=$boot_dev\"|g' $bootconf" 0
            fi
            ;;
        s390x)
            bootconf="/etc/zipl.conf"
            rlRun "sed -i $sed_options 's/ fips=[01] boot=$boot_dev/ /g' $bootconf" 0
            rlRun "sed -i $sed_options 's/parameters=\"\(.*\)\"/parameters=\"\1 fips=1 boot=$boot_dev\"/g' $bootconf" 0
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

    # fipsBOOTDEV=`df -P /boot/ | tail -1 | awk '{print $1}'`
    # if [ -z "$fipsBOOTDEV" ]; then
    #     rlLogError "Unable to detect /boot device name!"

    #     # debug
    #     df /boot/

    #     return 1
    # fi

    # if [[ "${USE_UUID:-yes}" != "no" && "${USE_UUID:-1}" != "0" ]]; then
        
    #     UUID=$(blkid -s UUID -o value $fipsBOOTDEV)
    #     if [ -z "$UUID" ]; then
    #         rlLogError "Unable to detect boot device UUID!"
                
    #         # debug
    #         df /boot
    #         blkid -s UUID -o value $fipsBOOTDEV
            
    #         return 1
    #     fi
        
    #     fipsBOOTDEV="UUID=$UUID"               
    # fi
    
    # fipsBOOTCONFIG="/boot/grub2/grub.cfg"
    # case "$(uname -i)" in
    #     i386|x86_64)
    #         rlCheckRpm "grub2" || fipsBOOTCONFIG="/boot/grub/grub.conf"
    #         ;;
    #     ia64)
    #         fipsBOOTCONFIG="/etc/elilo.conf"
    #         ;;
    #     ppc|ppc64)
    #         rlCheckRpm "grub2" || fipsBOOTCONFIG="/boot/etc/yaboot.conf"
    #         ;;
    # esac            
    # rlLog "Setting fipsBOOTCONFIG=$fipsBOOTCONFIG"

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

