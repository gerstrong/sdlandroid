#!/bin/sh

ARCH_LIST="arm64-v8a armeabi-v7a x86_64 x86"

PARALLEL=false

mkdir -p build

build() {
	ARCH=$1
	NO_ASM=""

	if [ -d "lib-$ARCH" ]; then
	  exit 0
	fi

	case $ARCH in
		armeabi-v7a)
			#NO_ASM="-DOPENSSL_NO_ASM=1" # Assembler in OpenSSL is broken when using clang
			export CONFIGURE_ARCH=android-arm
			;;
		x86)
			export CONFIGURE_ARCH=android-x86
			;;
		arm64-v8a)
			export CONFIGURE_ARCH=android-arm64
			;;
		x86_64)
			#NO_ASM="-DOPENSSL_NO_ASM=1" # Assembler in OpenSSL is broken when using clang
			export CONFIGURE_ARCH=android64-x86_64 # No-asm variant
			;;
		*)
			echo "Arch $ARCH not defined"
			exit 1;;
	esac

	rm -rf build/$ARCH
	mkdir -p build/$ARCH
	cd build/$ARCH

	tar -x -v -z -f ../../openssl-1.1.1j.tar.gz --strip=1
	patch -p1 < ../../config.patch || exit 1

	NDK=`which ndk-build`
	NDK=`dirname $NDK`
	NDK=`readlink -f $NDK`
	export CROSS_SYSROOT=$NDK/sysroot/usr
	export ANDROID_NDK_HOME=$NDK

	env LDFLAGS="" \
		CFLAGS="$NO_ASM" \
		../../setCrossEnvironment-$ARCH.sh \
#		ln -s $AR `basename -s -clang $CC`-ar
#		export PATH=`pwd`:`dirname $CC`:$PATH
#		export ANDROID_NDK_HOME=`dirname $CC`/..
#		export CC=clang
#		export AR=ar
		sh -c 'env PATH=`dirname $CC`:$PATH \
		./Configure no-shared --prefix=`pwd`/dist --openssldir=. $CONFIGURE_ARCH -fPIC' \
		|| exit 1

	sed -i.old 's/^CNF_CPPFLAGS=.*/CNF_CPPFLAGS=/' Makefile
	sed -i.old 's/^CNF_CFLAGS=.*/CNF_CFLAGS=/' Makefile
	sed -i.old 's/^CNF_CXXFLAGS=.*/CNF_CXXFLAGS=/' Makefile
	sed -i.old 's/^CNF_LDFLAGS=.*/CNF_LDFLAGS=/' Makefile
	#sed -i.old 's/^SHLIB_VERSION_NUMBER=.*/SHLIB_VERSION_NUMBER=sdl.1.so/' Makefile
	if [ "$ARCH" = armeabi-v7a ]; then
		sed -i.old 's/-DPOLY1305_ASM //' Makefile
		sed -i.old 's@crypto/poly1305/poly1305-armv4.S @@' Makefile
		sed -i.old 's@crypto/poly1305/poly1305-armv4.o @@' Makefile
	fi

	env LDFLAGS="" \
		CFLAGS="$NO_ASM" \
		../../setCrossEnvironment-$ARCH.sh \
		sh -c '
		export PATH=`pwd`:`dirname $CC`:$PATH
		make -j8' \
		|| exit 1

	cd ../..

	rm -rf lib-$ARCH
	mkdir -p lib-$ARCH
#	cp build/$ARCH/libcrypto.so.sdl.1.so lib-${ARCH}/libcrypto.so.sdl.1.so || exit 1
#	cp build/$ARCH/libssl.so.sdl.1.so lib-${ARCH}/libssl.so.sdl.1.so || exit 1
	cp build/$ARCH/libcrypto.a lib-${ARCH}/libcrypto.a || exit 1
	cp build/$ARCH/libssl.a lib-${ARCH}/libssl.a || exit 1
}


if $PARALLEL; then
	PIDS=""
	for ARCH in $ARCH_LIST; do
		build $ARCH &
		PIDS="$PIDS $!"
	done

	for PID in $PIDS; do
		wait $PID || exit 1
	done
else
	for ARCH in $ARCH_LIST; do
		build $ARCH || exit 1
	done
fi

rm -rf include
cp -r -L build/arm64-v8a/include ./ || exit 1
patch -p1 < opensslconf.h.patch || exit 1

rm -rf build
