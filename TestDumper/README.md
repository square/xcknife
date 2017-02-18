# TestDumper - EXPERIMENTAL

Utility that replaces xctool for enumerating tests. It requires the `build-for-testing` feature Xcode8 introduced on xcodebuild. In particular, it leverages the xctestrun file (see `man xcodebuild.xctestrun`).

## Building.

Run 

```
$ ./build.sh
````

## Using as command line tool

```
$ xcknife-test-dumper --help
Usage: xcknife-test-dumper [options] derived_data_folder output_file [device_id]
    -d, --debug                      Debug mode enabled
    -r, --retry-count COUNT          Max retry count for simulator output
    -t OUTPUT_FOLDER,                Sets temporary Output folder
        --temporary-output
    -s, --scheme XCSCHEME_FILE       Reads environments variables from the xcscheme file
    -h, --help                       Show this message
```