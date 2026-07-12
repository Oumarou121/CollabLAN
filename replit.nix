{pkgs}: {
  deps = [
    pkgs.ninja
    pkgs.gcc13
    pkgs.pkg-config
    pkgs.openssl
    pkgs.qt6.full
    pkgs.cmake
  ];
}
