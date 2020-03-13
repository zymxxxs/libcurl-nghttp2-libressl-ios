#!/bin/bash
set -e

# Custom build options
# CUSTOMCONFIG="enable-ssl-trace"

# Formatting
default="\033[39m"
wihte="\033[97m"
green="\033[32m"
red="\033[91m"
yellow="\033[33m"

bold="\033[0m${green}\033[1m"
subbold="\033[0m${green}"
archbold="\033[0m${yellow}\033[1m"
normal="${white}\033[0m"
dim="\033[0m${white}\033[2m"
alert="\033[0m${red}\033[1m"
alertdim="\033[0m${red}\033[2m"

# set trap to help debug build errors
trap 'echo -e "${alert}** ERROR with Build - Check /tmp/libressl*.log${alertdim}"; tail -3 /tmp/libressl*.log' INT TERM EXIT

LIBRESSL_VERSION="libressl-2.8.3"
IOS_MIN_SDK_VERSION="7.1"
IOS_SDK_VERSION=""
TVOS_MIN_SDK_VERSION="9.0"
TVOS_SDK_VERSION=""

usage ()
{
	echo
	echo -e "${bold}Usage:${normal}"
	echo
	echo -e "  ${subbold}$0${normal} [-v ${dim}<libressl version>${normal}] [-s ${dim}<iOS SDK version>${normal}] [-t ${dim}<tvOS SDK version>${normal}] [-e] [-x] [-h]"
	echo
	echo "         -v   version of libressl (default $LIBRESSL)"
	echo "         -s   iOS SDK version (default $IOS_MIN_SDK_VERSION)"
	echo "         -t   tvOS SDK version (default $TVOS_MIN_SDK_VERSION)"
	echo "         -e   compile with engine support"	
	echo "         -x   disable color output"
	echo "         -h   show usage"	
	echo
	trap - INT TERM EXIT
	exit 127
}

engine=0

while getopts "v:s:t:exh\?" o; do
    case "${o}" in
        v)
	    	LIBRESSL_VERSION="libressl-${OPTARG}"
            ;;
        s)
            IOS_SDK_VERSION="${OPTARG}"
            ;;
        t)
	    	TVOS_SDK_VERSION="${OPTARG}"
            ;;
		e)
            engine=1
	    	;;
		x)
			bold=""
			subbold=""
			normal=""
			dim=""
			alert=""
			alertdim=""
			archbold=""
			;;
        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))

DEVELOPER=`xcode-select -print-path`

buildMac()
{
	ARCH=$1

	echo -e "${subbold}Building ${LIBRESSL_VERSION} for ${archbold}${ARCH}${dim}"

	TARGET="darwin-i386-cc"

	if [[ $ARCH == "x86_64" ]]; then
		TARGET="--target=darwin64-x86_64-cc"
	fi

	export CC="${BUILD_TOOLS}/usr/bin/clang"

	pushd . > /dev/null
	cd "${LIBRESSL_VERSION}"
	./Configure --disable-asm ${TARGET} --enable-shared=false --prefix="/tmp/${LIBRESSL_VERSION}-${ARCH}" --with-openssldir="/tmp/${LIBRESSL_VERSION}-${ARCH}" $CUSTOMCONFIG &> "/tmp/${LIBRESSL_VERSION}-${ARCH}.log"
	make >> "/tmp/${LIBRESSL_VERSION}-${ARCH}.log" 2>&1
	make install_sw >> "/tmp/${LIBRESSL_VERSION}-${ARCH}.log" 2>&1
	# Keep openssl binary for Mac version
	cp "/tmp/${LIBRESSL_VERSION}-${ARCH}/bin/openssl" "/tmp/openssl"
	make clean >> "/tmp/${LIBRESSL_VERSION}-${ARCH}.log" 2>&1
	popd > /dev/null
}

buildIOS()
{
	ARCH=$1

	pushd . > /dev/null
	cd "${LIBRESSL_VERSION}"

	if [[ "${ARCH}" == "i386" || "${ARCH}" == "x86_64" ]]; then
		PLATFORM="iPhoneSimulator"
	else
		PLATFORM="iPhoneOS"
	fi

	export $PLATFORM
	export CROSS_TOP="${DEVELOPER}/Platforms/${PLATFORM}.platform/Developer"
	export CROSS_SDK="${PLATFORM}${IOS_SDK_VERSION}.sdk"
	export BUILD_TOOLS="${DEVELOPER}"
	export CC="${BUILD_TOOLS}/usr/bin/gcc"

	echo -e "${subbold}Building ${LIBRESSL_VERSION} for ${PLATFORM} ${IOS_SDK_VERSION} ${archbold}${ARCH}${dim}"

	if [[ "${ARCH}" == *"arm64"* || "${ARCH}" == "arm64e" ]]; then
		./Configure --disable-asm --host="arm-apple-darwin" --enable-shared=false --prefix="/tmp/${LIBRESSL_VERSION}-iOS-${ARCH}" --with-openssldir="/tmp/${LIBRESSL_VERSION}-iOS-${ARCH}" $CUSTOMCONFIG &> "/tmp/${LIBRESSL_VERSION}-iOS-${ARCH}.log"
	else
	    ./Configure --host="${ARCH}-apple-darwin" DSO_LDFLAGS=-fembed-bitcode --prefix="/tmp/${LIBRESSL_VERSION}-iOS-${ARCH}" --enable-shared=false --with-openssldir="/tmp/${LIBRESSL_VERSION}-iOS-${ARCH}" $CUSTOMCONFIG &> "/tmp/${LIBRESSL_VERSION}-iOS-${ARCH}.log"
	fi
	# add -isysroot to CC=
	sed -ie "s!^CFLAGS=!CFLAGS=-isysroot ${CROSS_TOP}/SDKs/${CROSS_SDK} -miphoneos-version-min=${IOS_MIN_SDK_VERSION} !" "Makefile"

	make >> "/tmp/${LIBRESSL_VERSION}-iOS-${ARCH}.log" 2>&1
	make install_sw >> "/tmp/${LIBRESSL_VERSION}-iOS-${ARCH}.log" 2>&1
	make clean >> "/tmp/${LIBRESSL_VERSION}-iOS-${ARCH}.log" 2>&1
	popd > /dev/null
}

buildTVOS()
{
	ARCH=$1

	pushd . > /dev/null
	cd "${LIBRESSL_VERSION}"

	if [[ "${ARCH}" == "x86_64" ]]; then
		PLATFORM="AppleTVSimulator"
	else
		PLATFORM="AppleTVOS"
		sed -ie "s!static volatile sig_atomic_t intr_signal;!static volatile intr_signal;!" "crypto/ui/ui_openssl.c"
	fi

	export $PLATFORM
	export CROSS_TOP="${DEVELOPER}/Platforms/${PLATFORM}.platform/Developer"
	export CROSS_SDK="${PLATFORM}${TVOS_SDK_VERSION}.sdk"
	export BUILD_TOOLS="${DEVELOPER}"
	export CC="${BUILD_TOOLS}/usr/bin/gcc -fembed-bitcode -arch ${ARCH}"
	export LC_CTYPE=C

	echo -e "${subbold}Building ${LIBRESSL_VERSION} for ${PLATFORM} ${TVOS_SDK_VERSION} ${archbold}${ARCH}${dim}"
	
	# Patch Configure to build for tvOS, not iOS
	LANG=C sed -i -- 's/D\_REENTRANT\:iOS/D\_REENTRANT\:tvOS/' "./Configure"
	chmod u+x ./Configure

	if [[ "${ARCH}" == "x86_64" ]]; then
		./Configure --disable-asm --host="${ARCH}-apple-darwin" --enable-shared=false --prefix="/tmp/${LIBRESSL_VERSION}-tvOS-${ARCH}" --with-openssldir="/tmp/${LIBRESSL_VERSION}-tvOS-${ARCH}" $CUSTOMCONFIG &> "/tmp/${LIBRESSL_VERSION}-tvOS-${ARCH}.log"
	else
		export CC="${BUILD_TOOLS}/usr/bin/gcc"
		./Configure --host="arm-apple-darwin" DSO_LDFLAGS=-fembed-bitcode --prefix="/tmp/${LIBRESSL_VERSION}-tvOS-${ARCH}" --enable-shared=false --with-openssldir="/tmp/${LIBRESSL_VERSION}-tvOS-${ARCH}" $CUSTOMCONFIG &> "/tmp/${LIBRESSL_VERSION}-tvOS-${ARCH}.log"
	fi
	# add -isysroot to CC=
	sed -ie "s!^CFLAGS=!CFLAGS=-isysroot ${CROSS_TOP}/SDKs/${CROSS_SDK} -mtvos-version-min=${TVOS_MIN_SDK_VERSION} !" "Makefile"

	make >> "/tmp/${LIBRESSL_VERSION}-tvOS-${ARCH}.log" 2>&1
	make install >> "/tmp/${LIBRESSL_VERSION}-tvOS-${ARCH}.log" 2>&1
	make clean >> "/tmp/${LIBRESSL_VERSION}-tvOS-${ARCH}.log" 2>&1
	popd > /dev/null
}


echo -e "${bold}Cleaning up${dim}"
rm -rf include/libressl/* lib/*

mkdir -p Mac/lib
mkdir -p iOS/lib
mkdir -p tvOS/lib
mkdir -p Mac/include/openssl/
mkdir -p iOS/include/openssl/
mkdir -p tvOS/include/openssl/

rm -rf "/tmp/${LIBRESSL_VERSION}-*"
rm -rf "/tmp/${LIBRESSL_VERSION}-*.log"

rm -rf "${LIBRESSL_VERSION}"

if [ ! -e ${LIBRESSL_VERSION}.tar.gz ]; then
	echo "Downloading ${LIBRESSL_VERSION}.tar.gz"
	curl -LO https://ftp.openbsd.org/pub/OpenBSD/LibreSSL/${LIBRESSL_VERSION}.tar.gz
else
	echo "Using ${LIBRESSL_VERSION}.tar.gz"
fi

if [[ "$LIBRESSL_VERSION" = "libressl-2.8.3" ]]; then
	echo "** Building libressl 2.8.3 **"
fi

echo "Unpacking openssl"
tar xfz "${LIBRESSL_VERSION}.tar.gz"

if [ "$engine" == "1" ]; then
	echo "+ Activate Static Engine"
	sed -ie 's/\"engine/\"dynamic-engine/' ${LIBRESSL_VERSION}/Configurations/15-ios.conf
fi

# echo -e "${bold}Building Mac libraries${dim}"
# buildMac "x86_64"

# echo "Copying headers and libraries"
# cp /tmp/${LIBRESSL_VERSION}-x86_64/include/openssl/* Mac/include/openssl/

# lipo \
# 	"/tmp/${LIBRESSL_VERSION}-x86_64/lib/libcrypto.a" \
# 	-create -output Mac/lib/libcrypto.a

# lipo \
# 	"/tmp/${LIBRESSL_VERSION}-x86_64/lib/libssl.a" \
# 	-create -output Mac/lib/libssl.a

# echo -e "${bold}Building iOS libraries${dim}"

# buildIOS "armv7"
# buildIOS "armv7s"
# buildIOS "arm64"
# buildIOS "arm64e"
# buildIOS "i386"
# buildIOS "x86_64"

# echo "  Copying headers and libraries"
# cp /tmp/${LIBRESSL_VERSION}-iOS-arm64/include/openssl/* iOS/include/openssl/

# lipo \
# 	"/tmp/${LIBRESSL_VERSION}-iOS-armv7/lib/libcrypto.a" \
# 	"/tmp/${LIBRESSL_VERSION}-iOS-armv7s/lib/libcrypto.a" \
# 	"/tmp/${LIBRESSL_VERSION}-iOS-i386/lib/libcrypto.a" \
# 	"/tmp/${LIBRESSL_VERSION}-iOS-arm64/lib/libcrypto.a" \
# 	"/tmp/${LIBRESSL_VERSION}-iOS-arm64e/lib/libcrypto.a" \
# 	"/tmp/${LIBRESSL_VERSION}-iOS-x86_64/lib/libcrypto.a" \
# 	-create -output iOS/lib/libcrypto.a

# lipo \
# 	"/tmp/${LIBRESSL_VERSION}-iOS-armv7/lib/libssl.a" \
# 	"/tmp/${LIBRESSL_VERSION}-iOS-armv7s/lib/libssl.a" \
# 	"/tmp/${LIBRESSL_VERSION}-iOS-i386/lib/libssl.a" \
# 	"/tmp/${LIBRESSL_VERSION}-iOS-arm64/lib/libssl.a" \
# 	"/tmp/${LIBRESSL_VERSION}-iOS-arm64e/lib/libssl.a" \
# 	"/tmp/${LIBRESSL_VERSION}-iOS-x86_64/lib/libssl.a" \
# 	-create -output iOS/lib/libssl.a


echo -e "${bold}Building tvOS libraries${dim}"
buildTVOS "arm64"
buildTVOS "x86_64"
echo "  Copying headers and libraries"
cp /tmp/${LIBRESSL_VERSION}-tvOS-arm64/include/openssl/* tvOS/include/openssl/

lipo \
	"/tmp/${LIBRESSL_VERSION}-tvOS-arm64/lib/libcrypto.a" \
	"/tmp/${LIBRESSL_VERSION}-tvOS-x86_64/lib/libcrypto.a" \
	-create -output tvOS/lib/libcrypto.a

lipo \
	"/tmp/${LIBRESSL_VERSION}-tvOS-arm64/lib/libssl.a" \
	"/tmp/${LIBRESSL_VERSION}-tvOS-x86_64/lib/libssl.a" \
	-create -output tvOS/lib/libssl.a

echo -e "${bold}Cleaning up${dim}"
rm -rf /tmp/${LIBRESSL_VERSION}-*
rm -rf ${LIBRESSL_VERSION}

#reset trap
trap - INT TERM EXIT

echo -e "${normal}Done"
