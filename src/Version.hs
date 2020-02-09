module Version (searchVersions) where

import Control.Applicative ((<|>))
import Data.Foldable (fold)
import Data.List (intersperse)
import Data.Monoid ((<>))
import System.Process (shell, readCreateProcess, CreateProcess(..))
import Text.Parsec (ParseError, many, many1, sepBy, parse, oneOf, between)
import Text.Parsec.Char (alphaNum, char, spaces, string, digit)
import Text.Parsec.String (Parser)

searchVersions :: FilePath -> IO [PackageVersion]
searchVersions path = do
    let
        command :: String
        command =
            "git rev-list master -- "
            <> path
            <> " | xargs -I{} git grep -E '^\\s+version\\s?=\\s?\"[^\"]+\"\\s*;\\s*$' {} -- "
            <> path

        nixpkgsRepoPath = "/Users/marcelo/Projects/nixpkgs"
    out <- readCreateProcess ((shell command) { cwd = Just nixpkgsRepoPath }) ""
    return $ either (error . show) id $ sequence $ fmap parsePackageVersion $ lines out


parsePackageVersion :: String -> Either ParseError PackageVersion
parsePackageVersion str = parse packageVersionParser "Package Version" str

data PackageVersion = PackageVersion
    --  Name of package. e.g. nodejs
    { packageName :: Maybe String
    -- package version. e.g. 10.12.0
    , packageVersion :: Version
    -- path of file where the version was found.
    -- e.g. pkgs/development/web/nodejs/default.nix
    , packagePath :: FilePath
    -- commit hash of nixpkgs with that version.
    , nixpkgsHash :: Hash
    } deriving (Show, Eq)

packageVersionParser :: Parser PackageVersion
packageVersionParser = do
    h <- hash
    char ':'
    p <- filePath
    char ':'
    spaces *> string "version" *> spaces *> char '=' *> spaces
    v <- inQuotes version
    return $ PackageVersion
        { packageName = Nothing
        , packageVersion = v
        , packagePath = p
        , nixpkgsHash = h
        }

newtype Hash = Hash String
    deriving (Show, Eq)

hash :: Parser Hash
hash = Hash <$> many alphaNum

newtype Version = Version String
    deriving (Show, Eq)

version :: Parser Version
version = Version <$> (many digit `separatedBy` '.')

inQuotes :: Parser a -> Parser a
inQuotes = between (char '"') (char '"')

filePath :: Parser FilePath
filePath = aName `separatedBy` '/'

separatedBy :: Parser String -> Char -> Parser String
separatedBy p separator =
    fold . intersperse [separator] <$> p `sepBy` char separator



-- | A valid directory/file name
aName :: Parser String
aName = many1 (alphaNum <|> char '-' <|> char '_' <|> char ' ' <|> char '.')
