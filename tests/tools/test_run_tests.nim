import std/unittest

import ../../tools/run_tests

suite "test runner sharding":
  test "one shard preserves every value in order":
    let values = @["a", "b", "c", "d"]
    check values.selectTestShard(0, 1) == values

  test "multiple shards partition values without overlap or loss":
    let values = @["a", "b", "c", "d", "e", "f", "g"]
    check values.selectTestShard(0, 3) == @["a", "d", "g"]
    check values.selectTestShard(1, 3) == @["b", "e"]
    check values.selectTestShard(2, 3) == @["c", "f"]

  test "invalid shard definitions fail closed":
    expect ValueError:
      discard @["a"].selectTestShard(0, 0)
    expect ValueError:
      discard @["a"].selectTestShard(-1, 1)
    expect ValueError:
      discard @["a"].selectTestShard(1, 1)
