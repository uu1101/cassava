{-# LANGUAGE OverloadedStrings, ScopedTypeVariables #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}

module Main
    ( main
    ) where

import qualified Data.ByteString as B
import qualified Data.ByteString.Lazy as BL
import qualified Data.ByteString.Lazy.Char8 as BL8
import qualified Data.HashMap.Strict as HM
import Data.Int
import qualified Data.Text as T
import qualified Data.Text.Lazy as LT
import Data.Vector ((!))
import qualified Data.Vector as V
import Data.Word
import Test.HUnit
import Test.Framework as TF
import Test.Framework.Providers.HUnit as TF
import Test.QuickCheck
import Test.Framework.Providers.QuickCheck2 as TF

import Data.Csv

------------------------------------------------------------------------
-- Parse tests

decodesAs :: BL.ByteString -> [[B.ByteString]] -> Assertion
decodesAs input expected = assertResult input expected $ decode False input

decodesWithAs :: DecodeOptions -> BL.ByteString -> [[B.ByteString]] -> Assertion
decodesWithAs opts input expected =
    assertResult input expected $ decodeWith opts False input

assertResult :: BL.ByteString -> [[B.ByteString]]
             -> Either String (V.Vector (V.Vector B.ByteString)) -> Assertion
assertResult input expected res = case res of
    Right r  -> V.fromList (map V.fromList expected) @=? r
    Left err -> assertFailure $
                "      input: " ++ show (BL8.unpack input) ++ "\n" ++
                "parse error: " ++ err

encodesAs :: [[B.ByteString]] -> BL.ByteString -> Assertion
encodesAs input expected =
    encode (V.fromList (map V.fromList input)) @?= expected

encodesWithAs :: EncodeOptions -> [[B.ByteString]] -> BL.ByteString -> Assertion
encodesWithAs opts input expected =
    encodeWith opts (V.fromList (map V.fromList input)) @?= expected

namedEncodesAs :: [B.ByteString] -> [[(B.ByteString, B.ByteString)]]
               -> BL.ByteString -> Assertion
namedEncodesAs hdr input expected =
    encodeByName (V.fromList hdr)
    (V.fromList $ map HM.fromList input) @?= expected

namedDecodesAs :: BL.ByteString -> [B.ByteString]
               -> [[(B.ByteString, B.ByteString)]] -> Assertion
namedDecodesAs input ehdr expected = case decodeByName input of
    Right r  -> (V.fromList ehdr, expected') @=? r
    Left err -> assertFailure $
                "      input: " ++ show (BL8.unpack input) ++ "\n" ++
                "parse error: " ++ err
  where
    expected' = V.fromList $ map HM.fromList expected

testRfc4180 :: Assertion
testRfc4180 = (BL8.pack $
               "#field1,field2,field3\n" ++
               "\"aaa\",\"bb\n" ++
               "b\",\"ccc\"\n" ++
               "\"a,a\",\"b\"\"bb\",\"ccc\"\n" ++
               "zzz,yyy,xxx\n")
              `decodesAs`
              [["#field1", "field2", "field3"],
               ["aaa", "bb\nb", "ccc"],
               ["a,a", "b\"bb", "ccc"],
               ["zzz", "yyy", "xxx"]]

positionalTests :: [TF.Test]
positionalTests =
    [ testGroup "encode" $ map encodeTest
      [ ("simple",       [["abc"]],          "abc\r\n")
      , ("quoted",       [["\"abc\""]],      "\"\"\"abc\"\"\"\r\n")
      , ("quote",        [["a\"b"]],         "\"a\"\"b\"\r\n")
      , ("quotedQuote",  [["\"a\"b\""]],     "\"\"\"a\"\"b\"\"\"\r\n")
      , ("leadingSpace", [[" abc"]],         "\" abc\"\r\n")
      , ("comma",        [["abc,def"]],      "\"abc,def\"\r\n")
      , ("twoFields",    [["abc","def"]],    "abc,def\r\n")
      , ("twoRecords",   [["abc"], ["def"]], "abc\r\ndef\r\n")
      , ("newline",      [["abc\ndef"]],     "\"abc\ndef\"\r\n")
      ]
    , testGroup "encodeWith"
      [ testCase "tab-delim" $ encodesWithAs (defEnc { encDelimiter = 9 })
        [["1", "2"]] "1\t2\r\n"
      ]
    , testGroup "decode" $ map decodeTest
      [ ("simple",       "a,b,c\n",        [["a", "b", "c"]])
      , ("crlf",         "a,b\r\nc,d\r\n", [["a", "b"], ["c", "d"]])
      , ("noEol",        "a,b,c",          [["a", "b", "c"]])
      , ("blankLine",    "a,b,c\n\nd,e,f\n\n",
         [["a", "b", "c"], ["d", "e", "f"]])
      , ("leadingSpace", " a,  b,   c\n",  [[" a", "  b", "   c"]])
      ] ++ [testCase "rfc4180" testRfc4180]
    , testGroup "decodeWith"
      [ testCase "tab-delim" $ decodesWithAs (defDec { decDelimiter = 9 })
        "1\t2" [["1", "2"]]
      ]
    ]
  where
    encodeTest (name, input, expected) =
        testCase name $ input `encodesAs` expected
    decodeTest (name, input, expected) =
        testCase name $ input `decodesAs` expected
    defEnc = defaultEncodeOptions
    defDec = defaultDecodeOptions

nameBasedTests :: [TF.Test]
nameBasedTests =
    [ testGroup "encode" $ map encodeTest
      [ ("simple", ["field"], [[("field", "abc")]], "field\r\nabc\r\n")
      , ("twoFields", ["field1", "field2"],
         [[("field1", "abc"), ("field2", "def")]],
         "field1,field2\r\nabc,def\r\n")
      , ("twoRecords", ["field"], [[("field", "abc")], [("field", "def")]],
         "field\r\nabc\r\ndef\r\n")
      ]
    , testGroup "decode" $ map decodeTest
      [("simple", "field\r\nabc\r\n", ["field"], [[("field", "abc")]])
      , ("twoFields", "field1,field2\r\nabc,def\r\n", ["field1", "field2"],
         [[("field1", "abc"), ("field2", "def")]])
      , ("twoRecords", "field\r\nabc\r\ndef\r\n", ["field"],
         [[("field", "abc")], [("field", "def")]])
      ]
    ]
  where
    encodeTest (name, hdr, input, expected) =
        testCase name $ namedEncodesAs hdr input expected
    decodeTest (name, input, hdr, expected) =
        testCase name $ namedDecodesAs input hdr expected

------------------------------------------------------------------------
-- Conversion tests

instance Arbitrary B.ByteString where
    arbitrary = B.pack `fmap` arbitrary

instance Arbitrary BL.ByteString where
    arbitrary = BL.fromChunks `fmap` arbitrary

instance Arbitrary T.Text where
    arbitrary = T.pack `fmap` arbitrary

instance Arbitrary LT.Text where
    arbitrary = LT.fromChunks `fmap` arbitrary

-- A single column with an empty string is indistinguishable from an
-- empty line (which we will ignore.) We therefore encode at least two
-- columns.
roundTrip :: (Eq a, FromField a, ToField a) => a -> Bool
roundTrip x = case decode False (encode (V.singleton (x, dummy))) of
    Right v | V.length v == 1 -> let (y, _ :: Char) = v ! 0 in x == y
    _  -> False
  where dummy = 'a'

boundary :: forall a. (Bounded a, Eq a, FromField a, ToField a) => a -> Bool
boundary _dummy = roundTrip (minBound :: a) && roundTrip (maxBound :: a)

-- TODO: Right now we only encode ASCII properly. Should we support
-- UTF-8? Arbitrary byte strings?

conversionTests :: [TF.Test]
conversionTests =
    [ testGroup "roundTrip"
      [ testProperty "Char" (roundTrip :: Char -> Bool)
      , testProperty "ByteString" (roundTrip :: B.ByteString -> Bool)
      , testProperty "Int" (roundTrip :: Int -> Bool)
      , testProperty "Integer" (roundTrip :: Integer -> Bool)
      , testProperty "Int8" (roundTrip :: Int8 -> Bool)
      , testProperty "Int16" (roundTrip :: Int16 -> Bool)
      , testProperty "Int32" (roundTrip :: Int32 -> Bool)
      , testProperty "Int64" (roundTrip :: Int64 -> Bool)
      , testProperty "Word" (roundTrip :: Word -> Bool)
      , testProperty "Word8" (roundTrip :: Word8 -> Bool)
      , testProperty "Word16" (roundTrip :: Word16 -> Bool)
      , testProperty "Word32" (roundTrip :: Word32 -> Bool)
      , testProperty "Word64" (roundTrip :: Word64 -> Bool)
      , testProperty "lazy ByteString"
        (roundTrip :: BL.ByteString -> Bool)
      , testProperty "Text" (roundTrip :: T.Text -> Bool)
      , testProperty "lazy Text" (roundTrip :: LT.Text -> Bool)
      ]
    , testGroup "boundary"
      [ testProperty "Int" (boundary (undefined :: Int))
      , testProperty "Int8" (boundary (undefined :: Int8))
      , testProperty "Int16" (boundary (undefined :: Int16))
      , testProperty "Int32" (boundary (undefined :: Int32))
      , testProperty "Int64" (boundary (undefined :: Int64))
      , testProperty "Word" (boundary (undefined :: Word))
      , testProperty "Word8" (boundary (undefined :: Word8))
      , testProperty "Word16" (boundary (undefined :: Word16))
      , testProperty "Word32" (boundary (undefined :: Word32))
      , testProperty "Word64" (boundary (undefined :: Word64))
      ]
    ]

------------------------------------------------------------------------
-- Test harness

allTests :: [TF.Test]
allTests = [ testGroup "positional" positionalTests
           , testGroup "named" nameBasedTests
           , testGroup "conversion" conversionTests
           ]

main :: IO ()
main = defaultMain allTests
