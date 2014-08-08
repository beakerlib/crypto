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
	rlLog "FIPS mode is disabled"
	return 1
    fi
    return 2
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

    fipsBOOTCONFIG="/boot/grub2/grub.cfg"
    case $(uname -i); in
        i386|x86_64)
            rlCheckRpm "grub2" || fipsBOOTCONFIG="/boot/grub/grub.conf"
            ;;
        ia64)
            fipsBOOTCONFIG="/etc/elilo.conf"
            ;;
        ppc|ppc64)
            rlCheckRpm "grub2" || fipsBOOTCONFIG="/etc/yaboot.conf"
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

