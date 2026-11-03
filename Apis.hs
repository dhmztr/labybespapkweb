{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeOperators #-}
module Apis where

import Types
import Control.Concurrent (modifyMVar_)
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
import Cars (znajdzKierowce)
import Data.Time.Clock (getCurrentTime)
import Text.HTML.SanitizeXSS (sanitize)
import Data.Pool (Pool, withResource)
import Control.Monad.Error.Class (MonadError(throwError))
import Database.Redis qualified as R
import Data.ByteString.Char8 qualified as BC8
import Text.Regex.TDFA ((=~))


poprawnyEmail :: String -> Bool
poprawnyEmail email = email =~ ("^[^ ]+@[^ ]+\\.[^ ]+$" :: String)


passwordHash :: PasswordHash Argon2
passwordHash = PasswordHash "$argon2id$v=19$m=65536,t=2,p=1$PycdySns1NErahSML9ctNA$9HDgpC/b2j+us2dCmsrSnK4CRv3bHTYinpGDh10KM/0"
kierowcy :: MVar (M.Map String Kierowca) -> Handler ([Kierowca])
kierowcy mv = do
                inner <- liftIO (readMVar mv)

                return (M.elems inner)
zamowienie :: R.Connection -> MVar (M.Map String String) -> MVar (M.Map String Kierowca) -> Pool Connection -> Maybe String -> Zamowienie -> (Handler Kierowca)
zamowienie rconn mvprzejazdy mvkierowcy pool naglowek zamowieniereq = case naglowek of
    (Just rawtok) -> do
        case (stripPrefix "Bearer " rawtok) of
            Just validtoken -> do
                emailquery <- liftIO (pobierzEmail rconn validtoken )
                case emailquery of
                    (Just usermail) -> do
                        przejazdy <- liftIO (readMVar mvprzejazdy )
                        let mtokenAktywny = M.lookup usermail przejazdy 
                        dozwolone <- case mtokenAktywny of
                            Nothing -> return True
                            Just idkier -> do
                                mapaKierowcow <- liftIO (readMVar mvkierowcy)
                                case M.lookup idkier mapaKierowcow of
                                    Just k  -> return (cel k == Nothing)   -- skonczyl = wolno nowy
                                    Nothing -> return True


                                                            

                        if not dozwolone 
                            then throwError err409 
                        else
                         case zweryfikujZamowienie (lat_startowy zamowieniereq) (lon_startowy zamowieniereq) (lat_koncowy zamowieniereq ) (lon_koncowy zamowieniereq ) (miejsca zamowieniereq) of
                            Right zamowienieOk -> do
                                            kierowcymap <-(liftIO (readMVar mvkierowcy ))
                                            let kierowcy = M.elems kierowcymap 
                                        
                                            let kierowca = (znajdzKierowce ((lat_startowy zamowienieOk ) ,(lon_startowy zamowienieOk)) (miejsca zamowienieOk) kierowcy)
                                            liftIO (modifyMVar_ mvprzejazdy (\mapa -> pure (M.insert usermail (idKierowcy kierowca) mapa)))
                                            let zmodyfikowany = Kierowca (idKierowcy kierowca ) (lat kierowca) (lon kierowca ) 
                                                    (Just ((lat_startowy zamowienieOk ), (lon_startowy zamowienieOk )))
                                                    (Just ((lat_koncowy zamowienieOk ), (lon_koncowy zamowienieOk ))) (wolne_miejsca kierowca)

                                            let iduserquery = "SELECT id FROM users WHERE email = ?"
                                            iduseraraw <- 
                                                    liftIO (withResource pool $ \conn -> do 
                                                    query conn iduserquery (Only usermail) :: IO [Only Int])
                                            if length iduseraraw == 0 then throwError err403 {errBody = BL8.pack ("User doesnt exist in database")}
                                            else do 
                                                let idusera = head (map fromOnly iduseraraw)
                                                let insertquery = "INSERT INTO rides (client_id,vehicle_id,pickup_lat,pickup_lng,dropoff_lat,dropoff_lng) VALUES (?,?,?,?,?,?)"
                                                zwroconazbazy <- 
                                                    liftIO ( withResource pool $ \conn -> try (execute conn insertquery 
                                                                                            (idusera, (read (idKierowcy kierowca) :: Int), lat_startowy zamowienieOk, lon_startowy
                                                                                            zamowienieOk, lat_koncowy zamowienieOk, lon_koncowy zamowienieOk)))
                                                case zwroconazbazy of
                                                    Left ( e::SqlError ) -> throwError err500 
                                                    Right (_) -> do
                                                    
                                                        liftIO (modifyMVar_ mvkierowcy (\mapa -> pure (M.insert (idKierowcy kierowca) zmodyfikowany mapa ) ))
                                                        return zmodyfikowany 
                                                


                            Left powod -> throwError (err400{errBody = (BL8.pack ("Nie mozna ukonczyc zamowienia: " ++ powod))})
                    Nothing -> throwError (err401{errBody = BL8.pack ("Wygasly token ")})
            Nothing -> throwError err401
    Nothing -> throwError (err401{errBody = (BL8.pack "Brak tokenu autoryzujacego")})
rejestracja :: R.Connection -> Pool Connection -> Poswiadczenia -> (Handler Odpowiedz)
rejestracja rconn pool user = do
    let zapytanie = "INSERT INTO users (email,password_hash) Values (?,?)"
    if length (haslo user) <= 8
        then throwError err400 {errBody = (BL8.pack ("Zbyt krótkie hasło"))}
    else
        return ()
    if not (poprawnyEmail (email user))
        then throwError err400 {errBody = (BL8.pack ("Niepoprawny email"))}
    else
        return ()
    hash_haslo <- hashPassword $ (mkPassword (T.pack (haslo user)))
    operacja <- liftIO ( withResource  pool $ \conn -> try (execute conn zapytanie (email user, unPasswordHash (hash_haslo))))
    case operacja of
        Left (e :: SqlError)
            | sqlState e == "23505" -> throwError err409{errBody = (BL8.pack ("Uzytkownik istnieje"))}
            | otherwise -> throwError err500{errBody = (BL8.pack ("Nie udalo sie stworzyc konta"))}
        (Right _) -> do
            tok <- liftIO (generujToken)
            wynik <- liftIO (zapiszToken rconn tok (email user))
            if wynik then 
                pure (Odpowiedz tok)
            else
                throwError err500
login :: R.Connection -> Pool Connection -> Poswiadczenia -> (Handler Odpowiedz)
login rconn pool user = do
    rows <- liftIO (withResource pool $ \conn -> do (query conn "SELECT password_hash FROM users WHERE email = ?" (Only (email user)) :: IO [Only T.Text]))
    let (hash, istnieje) = case rows of
            (Only h : _) -> ((PasswordHash h), True)
            [] -> (passwordHash, False)
    if ((checkPassword (mkPassword (T.pack (haslo user))) hash) == PasswordCheckSuccess) && istnieje
        then do
            token <- liftIO generujToken
            wynik <- liftIO (zapiszToken rconn token (email user))
            if wynik 
                then

                return (Odpowiedz token)
            else
                throwError err500
        else
            throwError err401

zdrowie :: (Handler String)
zdrowie = return "ok"
ja :: R.Connection -> MVar (M.Map String String) -> MVar (M.Map String Kierowca) ->  Maybe String -> Handler JaOdpowiedz 
ja rconn mvprzejazdy mvkierowcy header = case header of
    Just x -> do
        case (stripPrefix "Bearer " x ) of
            Just validtoken -> do 
                emailquery <- liftIO (pobierzEmail rconn validtoken )
                case emailquery of
                 Nothing -> throwError err401 
                 Just (mail) -> do
                                mapaprzejazdy <- liftIO (readMVar mvprzejazdy )
                                case M.lookup mail mapaprzejazdy of
                                    Nothing -> return (JaOdpowiedz mail Nothing)
                                    Just (idK) -> do
                                                mapakierowcow <- liftIO (readMVar mvkierowcy )
                                                case M.lookup idK mapakierowcow  of
                                                    Nothing -> do
                                                        liftIO (modifyMVar_ mvprzejazdy (\mapa -> pure (M.delete mail mapa )))
                                                        return (JaOdpowiedz mail Nothing)
                                                    Just (kier) -> do
                                                            case (cel kier) of
                                                                Just (_,_) -> return (JaOdpowiedz mail (Just (idK )))
                                                                Nothing -> do
                                                                        liftIO (modifyMVar_ mvprzejazdy (\mapa -> pure (M.delete mail mapa )))
                                                                        return (JaOdpowiedz mail Nothing)




            Nothing -> throwError err401 
    Nothing -> throwError err401
wyloguj :: R.Connection -> Maybe String -> (Handler String) 
wyloguj rconn authtoken = case authtoken of 
                                Just tok -> do
                                        let strippedToken = stripPrefix "Bearer " tok 
                                        case strippedToken  of 
                                            Just validtoken -> do
                                                liftIO (usunToken rconn validtoken)
                                                pure "OK"
                                            Nothing -> throwError  err401 
                                Nothing -> throwError err401 
            
komentarzedlakierowcy ::  R.Connection  -> Pool Connection -> Maybe String -> KomentarzReq -> (Handler [Komentarz])
komentarzedlakierowcy rconn pool authtoken req = do
                        case authtoken of 
                            Nothing -> throwError err401 
                            Just (tok) -> do 
                                let strippedToken = stripPrefix "Bearer " tok 
                                case strippedToken  of
                                 Nothing -> throwError err401 
                                 (Just validToken ) -> do 
                                            emailquery <- liftIO (pobierzEmail rconn validToken )
                                            case emailquery of
                                                Nothing -> throwError err401 
                                                (Just _) -> do
                                                        
                                                    let idk = reqidkier req
                                                    queryresp <- (liftIO ( withResource pool $ \conn -> query conn "SELECT idKier,data,ocena,wystawiajacy,tresc FROM komentarze WHERE idKier = ?" (Only idk) :: IO [(String,String,Double,String, String)]))
                                                    let komentarze = map (\(x, y, z,a, b) -> zparsujkomentarze (x, y, z, a,b)) queryresp
                                                    return komentarze
                    
dodajKomentarz :: R.Connection -> Pool Connection -> Maybe String -> Komentarz -> (Handler String)
dodajKomentarz rconn pool authtoken kom = do
                    case authtoken of
                        Nothing -> throwError err401
                        Just (tok) -> do
                                    let strippedToken = stripPrefix "Bearer " tok 
                                    case strippedToken of
                                        (Just validToken) -> do
                                            emailquery <- liftIO (pobierzEmail rconn validToken )
                                            case emailquery of
                                                Nothing -> throwError err401 
                                                (Just wystawiajacyemail) ->  do
                                                    let zapytanie = "INSERT INTO komentarze (idKier,data,ocena,wystawiajacy,tresc) Values (?,?,?,?,?)"
                                                    aktualna_data <- liftIO (getCurrentTime )
                                                    let zweryfikowany = zweryfikujKomentarz (idKier kom) (show aktualna_data ) (ocena kom) wystawiajacyemail (tresc kom )
                                                    case zweryfikowany  of
                                                        (Left powod) -> throwError err406 {errBody = BL8.pack (powod )}
                                                        (Right poprawnykom) -> do

                                                            operacja <- liftIO (withResource pool $ \conn -> try (execute conn zapytanie ((idKier poprawnykom) ,(czasotrzymania poprawnykom ),(ocena poprawnykom),wystawiajacyemail , tresc poprawnykom)))
                                                            case operacja  of
                                                             Left (e :: SqlError ) -> throwError err500 
                                                             (Right _) ->  return "OK"
                                        Nothing -> throwError err401 
mojeZamowienia:: R.Connection -> Pool Connection -> Maybe String -> (Handler [Przejazd])
mojeZamowienia rconn pool authtoken = do 
                    case authtoken of
                        Nothing -> throwError err401
                        Just (tok) -> do
                                    let strippedToken = stripPrefix "Bearer " tok 
                                    case strippedToken of
                                        (Just validToken) -> do
                                            emailquery <- liftIO (pobierzEmail rconn validToken )
                                            case emailquery of
                                                Nothing -> throwError err401 
                                                (Just usermail) -> do
                                                        let iduserquery = "SELECT id FROM users WHERE email = ?"
                                                        iduseraraw <- liftIO (withResource pool $ \conn -> do 
                                                                query conn iduserquery (Only usermail) :: IO [Only Int])
                                                        let idusera = head (map fromOnly iduseraraw)
                                                        let ridesquery = "SELECT vehicle_id,pickup_lat,pickup_lng,dropoff_lat,dropoff_lng,status,created_at::text FROM rides WHERE client_id = ?"
                                                        przejazdyraw <- liftIO (withResource pool $ \conn -> 
                                                            query conn ridesquery (Only idusera) :: IO [( Int, Double, Double, Double, Double, String, String)]) 
                                                        let przejazdy = parseprzejazdy przejazdyraw
                                                        return przejazdy
                                                        


                                
generujToken :: IO String
generujToken = do
  bytesarr <- getRandomBytes 32 :: IO BS.ByteString
  let intarr = map fromIntegral (BS.unpack bytesarr)
  let hex = concatMap byteToHex intarr
  pure hex

byteToHex :: Int -> String
byteToHex number
  | length wynik == 1 = "0" ++ wynik
  | otherwise = wynik
 where
  wynik = showIntAtBase 16 intToDigit number ""


zweryfikujZamowienie :: Double -> Double -> Double -> Double -> Int -> Either String Zamowienie
zweryfikujZamowienie las los lak lok z 
  | las < 0 = Left "Niepoprawny adres startowy"
  | los < 0 = Left "Niepoprawny adres startowy"
  | lok < 0 = Left "Niepoprawny adres docelowy"
  | lak < 0 = Left "Niepoprawny adres docelowy"
  | (z > 4) || (z < 1) = Left "Ilosc pasazerow poza zasiegiem"
  | otherwise = Right (Zamowienie las los lak lok z)
zparsujkomentarze:: (String,String,Double,String,String) -> Komentarz
zparsujkomentarze (a, b, c, d,e) = Komentarz {idKier = a,czasotrzymania=b,ocena=c,wystawiajacy=d,tresc=e}

zweryfikujKomentarz :: String -> String -> Double -> String -> String -> Either String Komentarz
zweryfikujKomentarz idk datakom ocenakier wystawiajacykom tresckom 
    | null idk || length idk > 30 = Left "Niepoprawny kierowca"
    | null datakom || length datakom > 50 = Left "Niepoprawna data"
    | ocenakier > 5 || ocenakier < 0 = Left "Niepoprawna ocena"
    | null wystawiajacykom || length wystawiajacykom > 30 = Left "Niepoprawny wystawiajacy"
    | null tresckom || length tresckom > 500 = Left "Niepoprawna tresc komentarza"
    | otherwise = Right (Komentarz {idKier = sanitizeString idk,czasotrzymania=datakom ,ocena = ocenakier ,wystawiajacy= sanitizeString (wystawiajacykom ),tresc = sanitizeString (tresckom)})

                                    
    
                                
sanitizeString :: String -> String
sanitizeString wartosc = T.unpack (sanitize (T.pack wartosc ))

parseprzejazdy :: [(Int, Double, Double, Double, Double, String, String)] -> [Przejazd]
parseprzejazdy [] = []
parseprzejazdy ((a,b,c,d,e,f,g):reszta) = (Przejazd a b c d e f g  ):parseprzejazdy reszta


pobierzEmail :: R.Connection -> String -> IO (Maybe String)
pobierzEmail redisConn token = do
        wynik <- R.runRedis redisConn (R.get (BC8.pack token)) :: IO (Either R.Reply (Maybe BS.ByteString))
        case wynik of 
          Left _ -> return Nothing
          Right Nothing -> return Nothing
          Right (Just email) -> return (Just (BC8.unpack email))

zapiszToken :: R.Connection -> String -> String -> IO Bool
zapiszToken redisConn token mail = do
        wynik <- R.runRedis redisConn (R.setex (BC8.pack token) 3600 (BC8.pack mail)) :: IO (Either R.Reply R.Status)
        case wynik of 
          Left _ -> return False 
          Right _ -> return True
usunToken :: R.Connection -> String -> IO Integer
usunToken redisConn token = do
                            wynik <- R.runRedis redisConn (R.del [(BC8.pack token)])
                            case wynik of
                                Left _ -> return 0
                                (Right i) -> return i



