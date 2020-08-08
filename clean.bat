rm -rf stage
cd uriparser
rm -rf ALL_BUILD.vcxproj ALL_BUILD.vcxproj.filters ALL_BUILD.vcxproj.user CMakeCache.txt CMakeFiles Debug INSTALL.vcxproj INSTALL.vcxproj.filters INSTALL.vcxproj.user
rm -rf ZERO_CHECK.vcxproj ZERO_CHECK.vcxproj.filters ZERO_CHECK.vcxproj.user cmake_install.cmake test/config.h.in~ uriparser.dir uriparser.sdf uriparser.sln uriparser.suo uriparser.vcxproj uriparser.vcxproj.filters
rm -rf uriparser.vcxproj.user uriparserstatic.dir uriparserstatic.vcxproj uriparserstatic.vcxproj.filters uriparserstatic.vcxproj.user win32/Debug
cd contrib\vstudio\vc12
rm -rf ia64 x64 x86 uriparser.suo uriparser.sdf
cd ../../../..

