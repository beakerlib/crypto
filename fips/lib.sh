#!/bin/bash
# vim: dict=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   lib.sh of /distribution/Library/fips
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
#   library-prefix = fips
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

true <<'=cut'
=pod

=head1 NAME

distribution/fips - a set of helpers for FIPS 140 testing

=head1 DESCRIPTION

This is a library intended for FIPS 140 testing. It can check status of
FIPS 140 mode and it can enable FIPS 140 mode. Importing this library
with misconfigured (neither fully disabled nor fully enabled) FIPS 140 mode
will produce an error.

=cut

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#   Internal Functions and Variabled
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# shellcheck disable=SC2120
function _workarounds {

    # On RHEL-8, rpm cannot verify digests of rpms using MD5 digest in FIPS 140.
    # Unfortunately, older test rpms are do not have neither SHA1 nor SHA256 and
    # hence cannot be installed. Test installation si done by restraint and we 
    # have to workaround it not to check digests.
    #
    # We can only use the workaround on systems with restraint.
    if rlIsRHEL ">=8" && rlCheckRpm "restraint"; then

        rlLog "Apply workaround for installation test rpms with MD5 digest" 
        cat >/usr/local/bin/rstrnt-package-workaround.sh<<EOF
#!/bin/bash

tmp_dir=$(mktemp -d)

shift
operation=$1
shift
packages=$*

if [[ "$operation" == "remove" ]]; then

    dnf remove -y $packages

elif [[ "$operation" == "install" ]]; then

    pushd $tmp_dir
    dnf install --downloadonly -y --downloaddir . --skip-broken $packages
    rpm -Uhv --nodigest --nofiledigest --nodeps *.rpm
    popd
fi

rm -rf $tmp_dir
EOF

        rlRun "chmod a+x /usr/local/bin/rstrnt-package-workaround.sh" || return 1
        rlRun "echo 'RSTRNT_PKG_CMD=/usr/local/bin/rstrnt-package-workaround.sh' >/usr/share/restraint/pkg_commands.d/rhel" || return 1
    fi

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
        rlRun "killall prelink" 0,1 "Kill all prelinks"
        rlRun "sed -i 's/PRELINKING=.*/PRELINKING=no/g' /etc/sysconfig/prelink" 0 "Configure system not to use prelink"
        rlRun "sync" 0 "Commit change to disk"
        rlRun "killall prelink" 0,1 "Kill all prelinks (again)"
        rlRun "prelink -u -a" 0 "Un-prelink the system"
    fi

    return 0
}

function _enforceModulusBits {
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

    return 0
}

function _enableFIPS {

    if rlIsRHEL ">=10"; then

        # Since RHEL-10.0 there is no fips-mode-setup anymore (RHEL-65652).
        rlRun "update-crypto-policies --set FIPS" 0 "Enable FIPS policy" || return 1

    elif rlIsFedora || rlIsRHEL ">=8"; then

        # Use crypto-policies to set-up FIPS 140 mode.
        rlRun "FIPS_MODE_SETUP_SKIP_WARNING=1 fips-mode-setup --enable" 0 "Enable FIPS 140 mode" || return 1

    elif rlIsRHEL "6" "7"; then

        # Install dracut and dracut-fips on RHEL7 and RHEL6.
        rlCheckRpm "dracut" || rlRun "yum install dracut -y" 0 "Install dracut"
        rlCheckRpm "dracut-fips" || rlRun "yum install dracut-fips -y" 0 "Install dracut-fips"

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
    else
        rlLogError "Unsupported distro!"
        return 1
    fi

    return 0
}

function _modifyBootloader {

    # On Fedora, RHEL-8 and RHEL-9, fips-mode-setup binary modifies bootloader.
    if rlIsFedora || rlIsRHEL "8" "9"; then
        return 0
    fi

    # On RHEL-6, RHEL-7 and RHEL-10 there is no fips-mode-setup.
	boot_device="$(stat -c %d:%m /boot)"
	root_device="$(stat -c %d:%m /)"
	boot_device_opt=""
	if [ "$boot_device" != "$root_device" ]; then
        # Trigger autofs if boot is mounted by automount.boot.
        pushd /boot >/dev/null 2>&1 && popd
        FINDMNT_UUID="findmnt --first-only -t noautofs --noheadings --output uuid"
        if ! rlIsRHEL "6" "7"; then
            FINDMNT_UUID+=" --mountpoint"
        fi
        boot_uuid=$(
            $FINDMNT_UUID /boot --fstab ||  # priority
            $FINDMNT_UUID /boot
        )
        if [ -z "$boot_uuid" ]; then
            rlLogError "Boot device not identified!"
            return 1
        fi
        boot_device_opt=" boot=UUID=$boot_uuid"
    fi
    rlRun "grubby --update-kernel=ALL --args='fips=1 $boot_device_opt'" 0 "Add fips=1 to next kernel command line" || return 1

    if [ "$(uname -m)" == "s390x" ]; then
        rlRun "zipl" 0 "Apply zipl configuration" || return 1
    fi

    return 0
}


# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#   Functions and Variables
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

true <<'=cut'
=pod

=head1 VARIABLES

=head2 fipsMode

This variable holds state of FIPS mode at the time when library is loaded.

=over

=back

=head1 FUNCTIONS

=head2 fipsIsEnabled

Function check current state of FIPS 140 mode. Returns 0 if it is correctly
enabled, 1 if disabled and 2 otherwise (misconfiguration).

=over

=back

=cut

function fipsIsEnabled {

    local ret_val=2

    rlLog "Checking FIPS 140 mode status"

    # Check OpenSSL setting.
    if rlIsRHEL '>6.5'; then
        if [[ -n $OPENSSL_ENFORCE_MODULUS_BITS ]]; then
            rlLog "OpenSSL working in new FIPS mode, 1024 bit RSA disallowed!"
        else
            rlLog "OpenSSL working in compatibility FIPS mode, 1024 bit allowed"
        fi
    fi

    # Check kernelspace FIPS mode and crypto-policies status.
    # This only work if CONFIG_CRYPTO_FIPS is enabled in the kernel.
    local kernelspace_fips=0
    local check_fips=""
    if [ -e /proc/sys/crypto/fips_enabled ]; then
        kernelspace_fips=$(cat /proc/sys/crypto/fips_enabled)
        if rlIsFedora || rlIsRHEL "8" "9"; then
            check_fips=$(fips-mode-setup --check | grep "FIPS mode")
        fi
    fi

    # Check userspace FIPS mode.
    local userspace_fips=$(test -e /etc/system-fips && echo 1 || echo 0)

    # Check crypto policy.
    local cryptopolicy_fips=$(rlIsRHEL "<8" || update-crypto-policies --show)

    # Check FIPS mode.
    if rlIsRHEL "6" "7"; then

        # Since RHEL-6.5 and before RHEL-8.0, both userspace and
        # kernelspace need to be in FIPS mode.
        if [ "$kernelspace_fips" == "1" ] && [ "$userspace_fips" == "1" ]; then
            rlLog "FIPS mode is enabled"
            ret_val=0
        elif [ "$kernelspace_fips" == "0" ] && [ "$userspace_fips" == "0" ]; then
            rlLog "FIPS mode is disabled"
            ret_val=1
        fi

    elif rlIsRHEL "8" "9"; then

        # Since RHEL-8.0, both userspace and kernelspace need to be
        # in FIPS mode and FIPS crypto policy must be set, also
        # fips-mode-setup --check should report that enabling was
        # completed.
        if [ "$kernelspace_fips" == "1" ] && \
           [ "$userspace_fips" == "1" ]   && \
           [ "$cryptopolicy_fips" == "FIPS" ] && \
           [ "$check_fips" == "FIPS mode is enabled." ] ; then
            rlLog "FIPS mode is enabled"
            ret_val=0
        elif [ "$kernelspace_fips" == "0" ] && \
             [ "$userspace_fips" == "0" ]   && \
             [ "$cryptopolicy_fips" != "FIPS" ] && \
             [ "$check_fips" == "FIPS mode is disabled." ] ; then
            rlLog "FIPS mode is disabled"
            ret_val=1;
        fi

    elif rlIsRHEL ">=10"; then

        # Since RHEL-10.0 there is no fips-mode-setup and hence there
        # is no $check_fips check.
        if [ "$kernelspace_fips" == "1" ] && \
           [ "$cryptopolicy_fips" == "FIPS" ]; then
            rlLog "FIPS mode is enabled"
            ret_val=0
        elif [ "$kernelspace_fips" == "0" ] && \
             [ "$cryptopolicy_fips" != "FIPS" ]; then
            rlLog "FIPS mode is disabled"
            ret_val=1;
        fi

    elif rlIsFedora; then

        # Since Fedora-36 there is no /etc/system-fips and hence there is 
        # no $userspace_fips check.
        if [ "$kernelspace_fips" == "1" ] && \
           [ "$cryptopolicy_fips" == "FIPS" ] && 
           [ "$check_fips" == "FIPS mode is enabled." ] ; then
            rlLog "FIPS mode is enabled"
            ret_val=0
        elif [ "$kernelspace_fips" == "0" ] && \
             [ "$cryptopolicy_fips" != "FIPS" ] && \
             [ "$check_fips" == "FIPS mode is disabled." ] ; then
            rlLog "FIPS mode is disabled"
            ret_val=1;
        fi

    else
        rlLogError "Unsupported distro!"
    fi

    if [ $ret_val -eq 2 ]; then
        rlLog "FIPS mode is not correctly enabled!"
    fi
    if [ $ret_val -ne 0 ]; then
        rlLog "kernelspace fips mode = $kernelspace_fips"
        if rlIsRHEL "<10"; then
            rlLog "userspace fips mode = $userspace_fips"
        fi
        if rlIsFedora || rlIsRHEL ">=8"; then
            rlLog "crypto policy = $cryptopolicy_fips"
        fi
        if rlIsFedora || rlIsRHEL "8" "9"; then
            rlLog "fips-mode-setup --check = $check_fips"
        fi
    fi

    return $ret_val
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

    rlLog "Checking FIPS 140 support"

    # Check RHEL version.
    if [[ $rhel =~ 7\. ]] && [[ $kernel =~ ^4\. ]]; then
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
    elif [[ $ARCH =~ aarch ]] && ! rlIsRHEL '>=8'; then
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

Function enables FIPS 140 mode. Enablement must be completed by system restart.
Returns 0 if enabling was successful, 1 otherwise.

=over

=back

=cut
function fipsEnable {

    rlLog "Enabling FIPS 140 mode"

    # Turn-off prelink (if prelink is installed).
    _disablePrelink || return 1

    # Enforce 2048 bit limit on RSA and DSA generation (RHBZ#1039105).
    _enforceModulusBits || return 1

    # Workarounds for testing in FIPS 140 mode.
    _workarounds || return 1

    # Enable FIPS 140 mode.
    _enableFIPS || return 1

    # Modify bootloader.
    _modifyBootloader || return 1

    # Success.
    return 0
}


true <<'=cut'
=pod

=head2 fipsLibraryLoaded

Initialization callback.
Importing this library with misconfigured (neither fully disabled nor
fully enabled) FIPS 140 mode will produce an error.

=over

=back

=cut
function fipsLibraryLoaded {

    # In Fedora, fips-mode-setup is separate package, but cannot 
    # be installed via fips library dependecies.
    if rlIsFedora && ! which fips-mode-setup >/dev/null 2>&1; then
        rlLog "Installing Missing fips-mode-setup package"
        rlRun "dnf install fips-mode-setup -y" 
    fi

    # In RHEL 8.3+ and Fedora, scripts are in crypto-policies-scripts
    if rlIsFedora || rlIsRHEL "8" "9" && (
            ! command -v fips-mode-setup >/dev/null 2>&1 ||
            ! command -v update-crypto-policies >/dev/null 2>&1); then
        rlLog "Installing missing crypto-policies-scripts package"
        rlRun "dnf install crypto-policies-scripts -y --skip-broken"
    fi

    fipsIsEnabled 
    ret=$?
    
    if [ $ret == 0 ]; then
        fipsMode="enabled"
    elif [ $ret == 1 ]; then
        fipsMode="disabled"
    else
        fipsMode="error"
        rlFail "FIPS mode is already misconfigured, see above!"
    fi

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
