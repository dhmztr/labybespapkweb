
module Cars where
import Types
import Control.Concurrent (modifyMVar_, threadDelay)
import Control.Concurrent.MVar
import Control.Exception (try)
import Control.Monad.IO.Class (MonadIO (liftIO))
import Crypto.Random (MonadRandom (getRandomBytes))
import Data.Aeson
import Data.ByteString qualified as BS
import Data.ByteString.Lazy.Char8 qualified as BL8
import Data.Char (intToDigit)
import Data.Map qualified as M
import Data.Password.Argon2
import Data.Swagger (Swagger, ToSchema)
import Data.Text qualified as T
import Database.PostgreSQL.Simple
import GHC.Generics (Generic)
import Network.Wai.Handler.Warp (run)
import Numeric (showIntAtBase)
import Servant
import Servant.Swagger (toSwagger)
import Servant.Swagger.UI (SwaggerSchemaUI, swaggerSchemaUIServer)
import Data.List (stripPrefix, minimumBy)
import GHC.Base (Float)
import Types (Kierowca (lat, lon))
import Data.Function (on)
import System.Random (randomRIO,StdGen,uniformR )
krok :: Double
krok = 0.01
cityQuad :: [Point]
cityQuad =
    [ (51.2302, 16.9939) -- A
    , (51.1211, 17.2162) -- B
    , (51.0812, 16.9172) -- C
    , (51.038, 17.1099) -- D
    ]
petlaKierowcy :: MVar (M.Map String Kierowca) -> String -> IO ()
petlaKierowcy mv idK = do
          threadDelay 1000000
          deltaLat <- randomRIO (-0.01 ,0.01) :: IO Double
          deltaLon <- randomRIO (-0.01, 0.01)  :: IO Double
          inside <- readMVar mv 
          let kierowca = inside M.! idK 
          case (cel kierowca) of 
                    Nothing -> do 
                          let nowy_lat = lat kierowca + deltaLat
                          let nowy_lon = lon kierowca + deltaLon
                          if inPolygon cityQuad (nowy_lat, nowy_lon)
                           then do
                            let nowyKierowca = Kierowca idK nowy_lat nowy_lon Nothing Nothing (wolne_miejsca kierowca)
                            modifyMVar_ mv (\mapa -> pure (M.insert idK nowyKierowca mapa))
                           else 
                            return ()
                    Just (lat_dest ,lon_dest) -> do 
                                            let nowy_lat = (lat kierowca) + signum (lat_dest - (lat kierowca )) * krok 
                                            let nowy_lon = (lon kierowca) + signum (lon_dest - (lon kierowca )) * krok 
                                            if odleglosc (lat_dest,lon_dest) (kierowca {  lat = nowy_lat, lon = nowy_lon }) <= krok 
                                              then 
                                                case celKoncowy kierowca of
                                                  Nothing -> modifyMVar_ mv (\mapa -> pure (M.insert idK (Kierowca {idKierowcy = idK, lat = nowy_lat ,lon = nowy_lon ,cel = Nothing,celKoncowy = Nothing,wolne_miejsca = (wolne_miejsca kierowca )}) mapa ))
                                                  (Just (lat_cel,lon_cel)) -> 
                                                    modifyMVar_ mv (\mapa -> pure (M.insert idK (Kierowca 
                                                    {idKierowcy = idK ,lat=nowy_lat ,lon=nowy_lon ,cel = Just (lat_cel ,lon_cel ),
                                                    celKoncowy=Nothing,wolne_miejsca= (wolne_miejsca kierowca )}) mapa))
                                              else modifyMVar_ mv (\mapa -> pure (M.insert idK (kierowca {idKierowcy = idK, lat = nowy_lat ,lon = nowy_lon ,cel = (cel kierowca ),celKoncowy = (celKoncowy kierowca), wolne_miejsca = (wolne_miejsca kierowca )}) mapa ))
          petlaKierowcy mv idK

                                        
                                                    



znajdzKierowce :: (Double,Double) -> Int -> [Kierowca] -> Kierowca 
znajdzKierowce (latpas,longpas) wymagane_miejsca kierowcy = do
                                            let dostepni_kierowcy = filter (\x -> (wolne_miejsca x >= wymagane_miejsca && cel x == Nothing ) ) kierowcy 
                                            let odleglosci = map (\x -> (x,(odleglosc (latpas, longpas) x))) dostepni_kierowcy 
                                            let (kierowca, dystans) = minimumBy (compare `on `snd ) odleglosci 
                                            kierowca 


odleglosc:: (Double,Double) -> Kierowca -> Double
odleglosc (latpas,longpas) kierowca = abs (latpas - (lat kierowca)) + abs (longpas - (lon kierowca))
                    
                    
                              
type Point = (Double, Double)
inPolygon :: [Point] -> Point -> Bool
inPolygon poly (px, py) = odd (length crossings)
    where
      edges = zip poly (drop 1 poly ++ [head poly])
      crossings = filter crosses edges
      crosses ((x1, y1), (x2, y2)) =
        ((y1 > py) /= (y2 > py))
          && (px < (x2 - x1) * (py - y1) / (y2 - y1) + x1)
triangularR :: (Double, Double) -> StdGen -> (Double, StdGen)
triangularR (lo, hi) g0 =
    let (a, g1) = uniformR (lo, hi) g0
        (b, g2) = uniformR (lo, hi) g1
     in ((a + b) / 2, g2)

randomInQuad :: [Point] -> StdGen -> (Point, StdGen)
randomInQuad poly = go
    where
      lats = map fst poly
      lons = map snd poly
      (latLo, latHi) = (minimum lats, maximum lats)
      (lonLo, lonHi) = (minimum lons, maximum lons)
      go g0 =
        let (lat, g1) = triangularR (latLo, latHi) g0
            (lon, g2) = triangularR (lonLo, lonHi) g1
         in if inPolygon poly (lat, lon) then ((lat, lon), g2) else go g2
