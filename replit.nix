{pkgs}: {
  deps = [
    pkgs.ninja
    pkgs.gcc
    pkgs.pkg-config
    pkgs.openssl
    pkgs.qt6.qtwebsockets
    pkgs.qt6.qttools
    pkgs.qt6.qtdeclarative
    pkgs.qt6.qtbase
    pkgs.cmake
  ];
}
