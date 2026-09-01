cmake_minimum_required(VERSION 3.14)
project(SignerUiPlugin LANGUAGES CXX)

if(DEFINED ENV{LOGOS_MODULE_BUILDER_ROOT})
    include($ENV{LOGOS_MODULE_BUILDER_ROOT}/cmake/LogosModule.cmake)
else()
    message(FATAL_ERROR "LogosModule.cmake not found. Set LOGOS_MODULE_BUILDER_ROOT.")
endif()

# SOURCES must be listed explicitly — the macro does not glob.
logos_module(
    NAME signer_ui
    REP_FILE src/signer_ui.rep
    SOURCES
        src/signer_ui_backend.h
        src/signer_ui_backend.cpp
    # Offline calldata decoding. A static archive, so it is linked in and no
    # library file lands beside the plugin for ui-host to mistake for one.
    EXTERNAL_LIBS
        logos_tx_decoder
    INCLUDE_DIRS
        src
)
