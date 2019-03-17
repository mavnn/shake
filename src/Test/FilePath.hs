
module Test.FilePath(main) where

import Development.Shake.FilePath
import Development.Shake
import qualified System.FilePath as Native
import Test.Type
import Test.QuickCheck
import Control.Monad
import Data.List
import qualified Data.ByteString.Char8 as BS
import qualified Development.Shake.Internal.FileName as BS
import System.Info.Extra
import System.Directory
import qualified System.IO.Extra as IO


newtype File = File String deriving Show

instance Arbitrary File where
    arbitrary = fmap File $ listOf $ oneof $ map return "a /\\:."
    shrink (File x) = map File $ shrink x


main = testSimple $ do
    let infix 1 ===
        a === b = a Test.Type.=== b -- duplicate definition in QuickCheck 2.7 and above

    let norm x =
            let s = toStandard $ normaliseEx x
                b = BS.unpack (BS.filepathNormalise $ BS.pack x)
            in if s == b then s else error $ show ("Normalise functions differ",x,s,b)

    -- basic examples
    norm "" === "."
    norm "." === "."
    norm "/" === "/"
    norm "./" === "./"
    norm "/." === "/."
    norm "/./" === "/"
    norm "a/." === "a"
    norm "./a" === "a"
    norm "./a/." === "a"
    norm "./a/./" === "a/"
    norm "a/.." === "."
    norm "a/./.." === "."
    norm "a/../" === "./"
    norm "/a/../" === "/"
    norm "/a/./../" === "/"
    norm "../a" === "../a"
    norm "/../a/" === "/../a/"

    -- more realistic examples
    norm "neil//./test/moo/../bar/bob/../foo" === "neil/test/bar/foo"
    norm "bar/foo" === "bar/foo"
    norm "bar/foo/" === "bar/foo/"
    norm "../../foo" === "../../foo"
    norm "foo/../..///" === "../"
    norm "foo/bar/../../neil" === "neil"
    norm "foo/../bar/../neil" === "neil"
    norm "/foo/bar" === "/foo/bar"
    norm "//./" === (if isWindows then "//" else "/")
    norm "//foo/./bar" === (if isWindows then "//foo/bar" else "/foo/bar")
    when isWindows $ norm "c:\\foo\\bar" === "c:/foo/bar"
    when isWindows $ normaliseEx "foo/bar\\baz" === "foo\\bar\\baz"
    Success{} <- quickCheckWithResult stdArgs{maxSuccess=1000} $ \(File x) ->
        let y = norm x
            sep = Native.isPathSeparator
            noDrive = if isWindows then drop 1 else id
            ps = [y /= ""
                 ,null x || (sep (head x) == sep (head y) && sep (last x) == sep (last y))
                 ,not $ "/./" `isInfixOf` y
                 ,not isWindows || '\\' `notElem` y
                 ,not $ "//" `isInfixOf` noDrive y
                 ,".." `notElem` dropWhile (== "..") (dropWhile (\x -> all isPathSeparator x || isDrive x) $ splitDirectories y)
                 ,norm y == y]
        in if and ps then True else error (show (x, y, ps))

    dropDirectory1 "aaa/bbb" === "bbb"
    dropDirectory1 "aaa/" === ""
    dropDirectory1 "aaa" === ""
    dropDirectory1 "" === ""

    takeDirectory1 "aaa/bbb" === "aaa"
    takeDirectory1 "aaa/" === "aaa"
    takeDirectory1 "aaa" === "aaa"

    replaceDirectory1 "root/file.ext" "directory" === "directory" ++ [pathSeparator] ++ "file.ext"
    replaceDirectory1 "root/foo/bar/file.ext" "directory" === "directory" ++ [pathSeparator] ++ "foo/bar/file.ext"

    searchPathSeparator === Native.searchPathSeparator
    pathSeparators === Native.pathSeparators

    if isWindows then
        toNative "//this is a///test\\here/" === "\\\\this is a\\\\\\test\\here\\"
     else
        toNative "//this is a///test\\here/" === "//this is a///test\\here/"

    -- check common manipulations work
    ("//*" <.> "foo") === "//*.foo"
    toStandard ("a" </> "b" </> "c" <//> "*" <.> "exe") === "a/b/c//*.exe"
    ("a" <//> "/b/c") === "a//b/c"

    -- check makeRelativeEx
    IO.withTempDir $ \ cwd -> do
        setCurrentDirectory cwd
        createDirectory (cwd </> "a")
        createDirectory (cwd </> "b")
        writeFile (toNative (cwd </> "b/file.out")) "foo"
        createDirectory (cwd </> "e")
        createDirectory (cwd </> "e/f")
        createDirectory (cwd </> "e/f/g")
        createFileLink  (cwd </> "e/f/g/") (cwd </> "c")

        let a ==== b = a >>= (=== b)
        -- If the second argument has the first as a prefix, then makeRelative is used.
        makeRelativeEx "/x/y/" "/x/y/z"
            ==== Just "z"
        -- If the seconds argument is already relative, then use that.
        makeRelativeEx (cwd </> "c") "../b/file.out"
            ==== Just "../b/file.out"
        makeRelativeEx "a" "b/file.out"
            ==== Just "b/file.out"
        -- Requires a ".." indirection.
        makeRelativeEx (cwd </> "a") (cwd </> "b/file.out")
            ==== Just "../b/file.out"
        -- Requires indirection through a symlink.
        makeRelativeEx (cwd </> "c") (cwd </> "b/file.out")
            ==== Just "../../../b/file.out"
        -- First argument is relative and second is absolute. The first argument
        -- should be relative to the CWD.
        makeRelativeEx "c" (cwd </> "b/file.out")
            ==== Just "../../../b/file.out"
        -- First argument contains a symlink and indirections.
        makeRelativeEx (cwd </> "c/../../../a") (cwd </> "b/file.out")
            ==== Just "../b/file.out"
