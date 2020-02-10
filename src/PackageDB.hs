{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DerivingStrategies #-}

module PackageDB (generate, getInfo) where

{-|
    This module takes care of finding the path of a package in the
    nixpkgs repo
-}

import Data.Aeson (FromJSON(..), ToJSON, eitherDecodeFileStrict, withObject, (.:), (.:?))
import Data.Hashable (Hashable)
import Data.HashMap.Strict (HashMap)
import Data.HashMap.Strict as Map
import Data.Maybe (fromMaybe)
import Data.Text (Text, pack)
import GHC.Generics (Generic)
import System.TimeIt (timeItNamed)
import Version (filePath)
import Text.Parsec (parse)

import qualified Data.HashMap.Strict as H

generate :: FilePath -> IO PackageDB
generate filePath = do
    putStrLn "Generating package database ..."
    eitherDB <- timeItNamed "Decoding file" $ eitherDecodeFileStrict filePath
    putStrLn "Package database generated."
    return $ either error createDB eitherDB

getInfo :: Text -> PackageDB -> Maybe PackageInfo
getInfo str = H.lookup str . unPackageDB

-- PackageDB

newtype PackageDB = PackageDB { unPackageDB :: HashMap PackageName PackageInfo }

-- PackageInfo

data PackageInfo = PackageInfo
    { pinfo_name :: PackageName
    -- Path of the package in the nixpkgs repo
    , pinfo_nixpath :: Maybe FilePath
    -- How many other modules exist in that path
    , pinfo_pathCount :: Int
    } deriving (Show)

createDB :: NixPkgsJSON -> PackageDB
createDB (NixPkgsJSON rawDB) = PackageDB db
    where
        db = Map.mapWithKey (packageInfo pathsDb) rawDB

        packageInfo paths name rawInfo =
            PackageInfo
                { pinfo_name = name
                , pinfo_nixpath = raw_nixpath rawInfo
                , pinfo_pathCount = fromMaybe 0 $ do
                    p <- raw_nixpath rawInfo
                    Map.lookup p paths
                }

        pathsDb = Map.foldrWithKey addPathCount mempty rawDB

        addPathCount name rawInfo paths =
            case raw_nixpath rawInfo of
              Nothing    -> paths
              Just aPath -> Map.insertWith (+) aPath 1 paths



-----------------------------------------------------

-- PackageName

type PackageName = Text

-- NixPkgsJSON

newtype NixPkgsJSON = NixPkgsJSON (HashMap PackageName RawPackageInfo)
    deriving (Generic)

instance ToJSON   NixPkgsJSON
instance FromJSON NixPkgsJSON where
    parseJSON = withObject "NixPkgsJSON " $ \v ->
        NixPkgsJSON <$> (v .: "packages")

-- RawPackageInfo

newtype RawPackageInfo = RawPackageInfo
    { raw_nixpath :: Maybe FilePath
    } deriving (Show, Eq, Generic)

instance Hashable RawPackageInfo
instance ToJSON   RawPackageInfo
instance FromJSON RawPackageInfo  where
    parseJSON = withObject "RawPackageInfo" $ \v ->
        RawPackageInfo . fmap removeLineNumber <$> (v .: "meta" >>= (.:? "position"))


-- | take some/path:123 and return some/path
removeLineNumber :: FilePath -> FilePath
removeLineNumber rawPath =
    case parse filePath "Remove line number" rawPath of
        Left _  -> rawPath
        Right f -> f