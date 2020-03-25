# XCKnife
[![Gem Version](https://badge.fury.io/rb/xcknife.svg)](https://badge.fury.io/rb/xcknife)
[![Build Status](https://travis-ci.org/square/xcknife.svg?branch=master)](https://travis-ci.org/square/xcknife)
[![Apache 2 licensed](https://img.shields.io/badge/license-Apache2-blue.svg)](https://github.com/square/xcknife/blob/master/LICENSE)

XCKnife is a tool that partitions XCTestCase tests in a way that minimizes total execution time (particularly useful for distributed test executions).
 
It works by leveraging [xctool's](https://github.com/facebook/xctool) [json-stream](https://github.com/facebook/xctool#included-reporters) reporter output.

XCKnife generates a list of only arguments meant to be pass to Xctool's [*-only* test arguments](https://github.com/facebook/xctool#testing), but alternatively could used to generate multiple xcschemes with the proper test partitions.

More information on XCKnife, go [here](https://developer.squareup.com/blog/xcknife-faster-distributed-tests-for-ios).
 
## Install

`$ gem install xcknife`

## Using as command line tool
 
```
$ xcknife --help
Usage: xcknife [options] worker-count historical-timings-json-stream-file [current-tests-json-stream-file]
    -p, --partition TARGETS          Comma separated list of targets. Can be used multiple times.
    -o, --output FILENAME            Output file. Defaults to STDOUT
    -a, --abbrev                     Results are abbreviated
    -x, --xcodebuild-output          Output is formatted for xcodebuild
    -h, --help                       Show this message
```

## Example 

The data provided on the [example](https://github.com/square/xcknife/tree/master/example) folder:

`$ xcknife  -p iPhoneTestTarget 3 example/xcknife-exemplar-historical-data.json-stream example/xcknife-exemplar.json-stream`

This will balance the tests onthe `iPhoneTestTarget` into 3 machines. The output is:

```json
{
  "metadata": {
    "worker_count": 3,
    "partition_set_count": 1,
    "total_time_in_ms": 910,
    "historical_total_tests": 5,
    "current_total_tests": 5,
    "class_extrapolations": 0,
    "target_extrapolations": 0
  },
  "partition_set_data": [
    {
      "partition_set": "iPhoneTestTarget",
      "size": 3,
      "imbalance_ratio": 1.0,
      "partitions": [
        {
          "shard_number": 1,
          "cli_arguments": [ "-only", "iPhoneTestTarget:iPhoneTestClassGama" ],
          "partition_imbalance_ratio": 0.9923076923076923
        },
        {
          "shard_number": 2,
          "cli_arguments": [ "-only", "iPhoneTestTarget:iPhoneTestClassAlpha,iPhoneTestClassDelta" ],
          "partition_imbalance_ratio": 1.0054945054945055
        },
        {
          "shard_number": 3,
          "cli_arguments": [ "-only", "iPhoneTestTarget:iPhoneTestClassBeta,iPhoneTestClassOmega" ],
          "partition_imbalance_ratio": 1.0021978021978022
        }]}]}
```

This provides a lot of data about the partitions and their imbalances (both internal to the partition sets, and amongst them).

If you only want the *-only* arguments, run with the `-a` flag:

`$ xcknife  -p iPhoneTestTarget 3 example/xcknife-exemplar-historical-data.json-stream example/xcknife-exemplar.json-stream -a`

outputing:

```json
[
  [
    [
      "-only",
      "iPhoneTestTarget:iPhoneTestClassGama"
    ],
    [
      "-only",
      "iPhoneTestTarget:iPhoneTestClassAlpha,iPhoneTestClassDelta"
    ],
    [
      "-only",
      "iPhoneTestTarget:iPhoneTestClassBeta,iPhoneTestClassOmega"
    ]
  ]
]
```

## Example: Multiple partition Sets

You can pass the partition flag mutliple times, so that XCKnife will do two level partitioning: inside each partition, and then for all partitions.
  
This is useful if each partition is tested against multiple devices, simulator versions or configurations. On the following example picture `CommonTestTarget` being tested against iPhones only, while `CommonTestTarget,iPadTestTarget` is tested against iPads.

`$ xcknife  -p CommonTestTarget -p CommonTestTarget,iPadTestTarget 6 example/xcknife-exemplar-historical-data.json-stream example/xcknife-exemplar.json-stream`

This will balance two partition sets: `CommonTestTarget` and `CommonTestTarget,iPadTestTarget` into 6 machines. The output is:

```json
{
  "metadata": {
    "worker_count": 6,
    "partition_set_count": 2,
    "total_time_in_ms": 8733,
    "historical_total_tests": 6,
    "current_total_tests": 7,
    "class_extrapolations": 1,
    "target_extrapolations": 0
  },
  "partition_set_data": [
    {
      "partition_set": "CommonTestTarget",
      "size": 1,
      "imbalance_ratio": 0.5480554313813143,
      "partitions": [
        {
          "shard_number": 1,
          "cli_arguments": [
            "-only",
            "CommonTestTarget:CommonTestClass"
          ],
          "partition_imbalance_ratio": 1.0
        }
      ]
    },
    {
      "partition_set": "CommonTestTarget,iPadTestTarget",
      "size": 5,
      "imbalance_ratio": 1.4519445686186858,
      "partitions": [
        {
          "shard_number": 2,
          "cli_arguments": [
            "-only",
            "iPadTestTarget:iPadTestClassTwo"
          ],
          "partition_imbalance_ratio": 3.0800492610837438
        },
        {
          "shard_number": 3,
          "cli_arguments": [
            "-only",
            "iPadTestTarget:iPadTestClassOne"
          ],
          "partition_imbalance_ratio": 0.6169950738916257
        },
        {
          "shard_number": 4,
          "cli_arguments": [
            "-only",
            "iPadTestTarget:iPadTestClassFour"
          ],
          "partition_imbalance_ratio": 0.6169950738916257
        },
        {
          "shard_number": 5,
          "cli_arguments": [
            "-only",
            "CommonTestTarget:CommonTestClass"
          ],
          "partition_imbalance_ratio": 0.3774630541871921
        },
        {
          "shard_number": 6,
          "cli_arguments": [
            "-only",
            "iPadTestTarget:iPadTestClassThree"
          ],
          "partition_imbalance_ratio": 0.30849753694581283
        }
      ]
    }
  ]
}
```

## Using as Ruby gem

Described [here](https://github.com/square/xcknife/tree/master/example).

## Minimizing json-stream files

XCKnife uses only a few attributes of a json-stream file. If you are storing the files in repository, you may want to remove unecessary data with `xcknife-min`. For example:

`$ xcknife-min example/xcknife-exemplar-historical-data.json-stream minified.json-stream` 

## Contributing

Any contributors to the master *xcknife* repository must sign the
[Individual Contributor License Agreement (CLA)]. It's a short form that covers
our bases and makes sure you're eligible to contribute.

When you have a change you'd like to see in the master repository, send a
[pull request]. Before we merge your request, we'll make sure you're in the list
of people who have signed a CLA.

[Individual Contributor License Agreement (CLA)]: https://spreadsheets.google.com/spreadsheet/viewform?formkey=dDViT2xzUHAwRkI3X3k5Z0lQM091OGc6MQ&ndplr=1
[pull request]: https://github.com/square/xcknife/pulls


## License

Copyright 2016 Square Inc.
 
Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0
 
Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
