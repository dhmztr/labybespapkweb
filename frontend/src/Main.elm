port module Main exposing (main)


import Browser
import Browser.Dom
import Dict exposing (Dict)
import Html exposing (Html)
import Html.Attributes exposing (id)
import Http
import Json.Decode as D
import Json.Encode as E
import Task
import Time
import Types exposing (..)
import Format exposing (aut, numerAuta, parsuj, zaokr4)
import Bledy exposing (opisBledu, opisBleduOpinii, opisBleduRejestracji, opisBleduZamowienia, sprawdzRejestracje)
import Api exposing (pobierzJa, pobierzKierowcow, pobierzKomentarze, pobierzPrzejazdy, pobierzStan, przywroc, wylogujNaSerwerze, wystawKomentarz, zaloguj, zamow, zarejestruj)
import View.Strona exposing (stronaGlowna)
import View.Aplikacja exposing (widokAplikacji)



port zapiszToken : String -> Cmd msg


port usunToken : () -> Cmd msg


{-| auta, które użytkownik może ocenić, zapamiętane w localStorage: { email: [id auta] }
-}
port zapiszOceny : E.Value -> Cmd msg


{-| flagi: { token: zapamiętany token albo null, oceny: to, co zapisał port zapiszOceny }
-}
main : Program D.Value Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }


{-| lista aut jest publiczna, więc odświeża się co 2 sekundy także na stronie głównej
-}
subscriptions : Model -> Sub Msg
subscriptions _ =
    Time.every 2000 Tik




pustaZamowienie : FormZamowienia
pustaZamowienie =
    { startLat = ""
    , startLon = ""
    , celLat = ""
    , celLon = ""
    , miejsca = "1"
    , ustawiam = Start
    , stan = ZamPisanie Nothing
    }


puste : FormKomentarzy
puste =
    { wybrany = Nothing
    , lista = ListaPusta
    , ocena = "5"
    , tresc = ""
    , wysylanie = False
    , blad = Nothing
    , info = Nothing
    }


{-| z aktywnym przejazdem od razu pokazujemy zakładkę zamówienia
-}
nowaSesja : Model -> String -> Ja -> Sesja
nowaSesja model token ja =
    { email = ja.email
    , token = token
    , strona =
        if ja.przejazd == Nothing then
            StronaAuta

        else
            StronaZamowienie
    , wybrane = Nothing
    , zam = pustaZamowienie
    , kom = puste
    , przejazd = ja.przejazd
    , doOceny = Maybe.withDefault [] (Dict.get ja.email model.oceny)
    , zakonczony = Nothing
    , wersja = 0
    , historia = HistoriaPusta
    }


poczatek : Model
poczatek =
    { email = ""
    , haslo = ""
    , powtorz = ""
    , tryb = Logowanie
    , stan = Formularz Nothing
    , flota = []
    , pytanie = "nas jest troje"
    , oceny = Dict.empty
    }


init : D.Value -> ( Model, Cmd Msg )
init flagi =
    let
        zapamietany =
            Result.withDefault Nothing (D.decodeValue (D.field "token" (D.nullable D.string)) flagi)

        oceny =
            Result.withDefault Dict.empty (D.decodeValue (D.field "oceny" (D.dict (D.list D.string))) flagi)

        model =
            { poczatek | oceny = oceny }
    in
    case zapamietany of
        Just token ->
            -- sesja z poprzedniej wizyty: sprawdzamy u backendu, czy token nadal działa
            ( { model | stan = Sprawdzanie }, Cmd.batch [ przywroc token, pobierzKierowcow ] )

        Nothing ->
            ( model, pobierzKierowcow )


{-| wraca do strony głównej, ale zostawia flotę i to, co ktoś wpisał w pytanie
-}
doStronyGlownej : Stan -> Model -> Model
doStronyGlownej stan model =
    { model | email = "", haslo = "", powtorz = "", tryb = Logowanie, stan = stan }



{-| po każdej zmianie sprawdzamy, czy lista aut do oceny się zmieniła, i jeśli tak,
zapisujemy ją w localStorage, żeby przeżyła odświeżenie strony
-}
update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    let
        ( nowy, cmd ) =
            przetworz msg model
    in
    case nowy.stan of
        Zalogowany s ->
            if Maybe.withDefault [] (Dict.get s.email nowy.oceny) == s.doOceny then
                ( nowy, cmd )

            else
                let
                    oceny =
                        if List.isEmpty s.doOceny then
                            Dict.remove s.email nowy.oceny

                        else
                            Dict.insert s.email s.doOceny nowy.oceny
                in
                ( { nowy | oceny = oceny }
                , Cmd.batch [ cmd, zapiszOceny (E.dict identity (E.list E.string) oceny) ]
                )

        _ ->
            ( nowy, cmd )


przetworz : Msg -> Model -> ( Model, Cmd Msg )
przetworz msg model =
    case msg of
        WpisanoEmail email ->
            ( { model | email = email }, Cmd.none )

        WpisanoHaslo haslo ->
            ( { model | haslo = haslo }, Cmd.none )

        WpisanoPowtorz powtorz ->
            ( { model | powtorz = powtorz }, Cmd.none )

        UstawTryb tryb ->
            ( { model | tryb = tryb, haslo = "", powtorz = "", stan = Formularz Nothing }
            , Cmd.none
            )

        Zaloguj ->
            ( { model | stan = Wysylanie }, zaloguj model.email model.haslo )

        Zarejestruj ->
            case sprawdzRejestracje model.email model.haslo model.powtorz of
                Just problem ->
                    ( { model | stan = Formularz (Just problem) }, Cmd.none )

                Nothing ->
                    ( { model | stan = Wysylanie }, zarejestruj model.email model.haslo )

        OdpowiedzLogin (Ok token) ->
            ( model, pobierzJa token )

        OdpowiedzLogin (Err blad) ->
            ( { model | stan = Formularz (Just (opisBledu blad)) }, Cmd.none )

        OdpowiedzRejestracja (Ok token) ->
            -- backend po rejestracji od razu zwraca token, więc logujemy jak po /login
            ( model, pobierzJa token )

        OdpowiedzRejestracja (Err blad) ->
            ( { model | stan = Formularz (Just (opisBleduRejestracji blad)) }, Cmd.none )

        OdpowiedzJa token (Ok ja) ->
            ( { model | haslo = "", powtorz = "", stan = Zalogowany (nowaSesja model token ja) }
            , Cmd.batch [ zapiszToken token, naGore ]
            )

        OdpowiedzJa _ (Err blad) ->
            ( { model | stan = Formularz (Just (opisBledu blad)) }, Cmd.none )

        OdpowiedzPrzywrocenie token (Ok ja) ->
            ( { model | stan = Zalogowany (nowaSesja model token ja) }, Cmd.none )

        OdpowiedzPrzywrocenie _ (Err (Http.BadStatus 401)) ->
            -- token wygasł albo został unieważniony
            ( { model | stan = Formularz Nothing }, usunToken () )

        OdpowiedzPrzywrocenie _ (Err blad) ->
            ( { model | stan = Formularz (Just (opisBledu blad)) }, Cmd.none )

        Wyloguj ->
            case model.stan of
                Zalogowany dane ->
                    -- lokalnie wylogowujemy od razu, nie czekając na backend
                    ( doStronyGlownej Wylogowany model
                    , Cmd.batch [ usunToken (), wylogujNaSerwerze dane.token, przewinDo "konto" ]
                    )

                _ ->
                    ( model, Cmd.none )

        OdpowiedzWyloguj _ ->
            ( model, Cmd.none )

        NicNieRob ->
            ( model, Cmd.none )

        WpisanoPytanie pytanie ->
            ( { model | pytanie = pytanie }, Cmd.none )

        Tik _ ->
            case model.stan of
                Zalogowany s ->
                    -- zalogowanemu sprawdzamy też /ja, bo tylko stamtąd wiadomo, czy przejazd trwa
                    ( model, Cmd.batch [ pobierzKierowcow, pobierzStan s.token s.wersja ] )

                _ ->
                    ( model, pobierzKierowcow )

        OdpowiedzStanu wersja (Ok ja) ->
            zSesja
                (\s ->
                    if wersja /= s.wersja then
                        -- odpowiedź na pytanie wysłane przed złożeniem zamówienia, już nieaktualna
                        ( s, Cmd.none )

                    else
                        case ( s.przejazd, ja.przejazd ) of
                            ( Just id, Nothing ) ->
                                -- backend zapomniał przejazd: auto dowiozło klienta, można je ocenić
                                ( { s | przejazd = Nothing, zakonczony = Just id, doOceny = id :: List.filter ((/=) id) s.doOceny }
                                , Cmd.none
                                )

                            ( _, nowy ) ->
                                ( { s | przejazd = nowy }, Cmd.none )
                )
                model

        OdpowiedzStanu _ (Err (Http.BadStatus 401)) ->
            sesjaWygasla model

        OdpowiedzStanu _ (Err _) ->
            ( model, Cmd.none )

        ZamknijKomunikat ->
            zSesja (\s -> ( { s | zakonczony = Nothing }, Cmd.none )) model

        OdpowiedzKierowcy (Ok lista) ->
            ( { model | flota = List.sortBy numerAuta lista }, Cmd.none )

        OdpowiedzKierowcy (Err _) ->
            -- lista odświeża się co 2 s, więc chwilowy błąd po prostu zostawia stare dane
            ( model, Cmd.none )

        IdzDo strona ->
            zSesja
                (\s ->
                    if strona == StronaPrzejazdy then
                        -- historię pobieramy przy każdym wejściu w zakładkę, więc zawsze jest aktualna
                        ( { s | strona = strona, historia = HistoriaLaduje }, pobierzPrzejazdy s.token )

                    else
                        ( { s | strona = strona }, Cmd.none )
                )
                model

        WybranoAuto id ->
            zSesja
                (\s ->
                    if s.strona == StronaKomentarze then
                        wybierzKierowce id { s | wybrane = Just id }

                    else
                        ( { s | wybrane = Just id }, Cmd.none )
                )
                model

        OtworzOpinie id ->
            zSesja
                (\s ->
                    let
                        ( s2, cmd ) =
                            wybierzKierowce id s
                    in
                    ( { s2 | strona = StronaKomentarze, wybrane = Just id }, cmd )
                )
                model

        WpisanoWsp pole wartosc ->
            zSesja (\s -> ( { s | zam = ustawPole pole wartosc s.zam }, Cmd.none )) model

        UstawPunkt punkt ->
            zSesja (\s -> let z = s.zam in ( { s | zam = { z | ustawiam = punkt } }, Cmd.none )) model

        KlikMapa lat lon ->
            zSesja
                (\s ->
                    let
                        z =
                            s.zam
                    in
                    case z.ustawiam of
                        Start ->
                            -- po ustawieniu startu przełączamy się od razu na cel
                            ( { s | zam = { z | startLat = zaokr4 lat, startLon = zaokr4 lon, ustawiam = Cel } }, Cmd.none )

                        Cel ->
                            ( { s | zam = { z | celLat = zaokr4 lat, celLon = zaokr4 lon } }, Cmd.none )
                )
                model

        WpisanoMiejsca miejsca ->
            zSesja (\s -> let z = s.zam in ( { s | zam = { z | miejsca = miejsca } }, Cmd.none )) model

        Zamow ->
            zSesja
                (\s ->
                    let
                        z =
                            s.zam
                    in
                    case Maybe.map5 (zamow s.token) (parsuj z.startLat) (parsuj z.startLon) (parsuj z.celLat) (parsuj z.celLon) (String.toInt z.miejsca) of
                        Just cmd ->
                            ( { s | zam = { z | stan = ZamWysylanie }, wersja = s.wersja + 1 }, cmd )

                        Nothing ->
                            ( { s | zam = { z | stan = ZamPisanie (Just "Podaj poprawne współrzędne albo kliknij na mapie.") } }, Cmd.none )
                )
                model

        OdpowiedzZamowienie (Ok kierowca) ->
            zSesja
                (\s ->
                    let
                        z =
                            s.zam
                    in
                    ( { s | zam = { z | stan = ZamPisanie Nothing }, przejazd = Just kierowca.id, zakonczony = Nothing, wersja = s.wersja + 1 }
                    , Cmd.none
                    )
                )
                model

        OdpowiedzZamowienie (Err (Http.BadStatus 401)) ->
            sesjaWygasla model

        OdpowiedzZamowienie (Err blad) ->
            zSesja (\s -> let z = s.zam in ( { s | zam = { z | stan = ZamPisanie (Just (opisBleduZamowienia blad)) } }, Cmd.none )) model

        NoweZamowienie ->
            zSesja (\s -> ( { s | zam = pustaZamowienie }, Cmd.none )) model

        OdpowiedzPrzejazdy (Err (Http.BadStatus 401)) ->
            sesjaWygasla model

        OdpowiedzPrzejazdy wynik ->
            zSesja
                (\s ->
                    case wynik of
                        Ok lista ->
                            ( { s | historia = HistoriaGotowa lista }, Cmd.none )

                        Err _ ->
                            ( { s | historia = HistoriaBlad }, Cmd.none )
                )
                model

        WybranoKierowce id ->
            zSesja (wybierzKierowce id) model

        OdpowiedzKomentarze _ (Err (Http.BadStatus 401)) ->
            sesjaWygasla model

        OdpowiedzKomentarze id wynik ->
            zSesja
                (\s ->
                    let
                        k =
                            s.kom
                    in
                    -- odpowiedź dla auta, które użytkownik już zmienił, ignorujemy
                    if k.wybrany /= Just id then
                        ( s, Cmd.none )

                    else
                        case wynik of
                            Ok lista ->
                                ( { s | kom = { k | lista = ListaGotowa lista } }, Cmd.none )

                            Err _ ->
                                ( { s | kom = { k | lista = ListaBlad } }, Cmd.none )
                )
                model

        WpisanoOcene ocena ->
            zSesja (\s -> let k = s.kom in ( { s | kom = { k | ocena = ocena } }, Cmd.none )) model

        WpisanoTresc tresc ->
            zSesja (\s -> let k = s.kom in ( { s | kom = { k | tresc = tresc } }, Cmd.none )) model

        WystawKomentarz ->
            zSesja
                (\s ->
                    let
                        k =
                            s.kom
                    in
                    case k.wybrany of
                        Nothing ->
                            ( { s | kom = { k | blad = Just "Najpierw wybierz auto.", info = Nothing } }, Cmd.none )

                        Just id ->
                            if not (List.member id s.doOceny) then
                                ( { s | kom = { k | blad = Just "Opinię wystawisz po zakończonym przejeździe tym autem.", info = Nothing } }, Cmd.none )

                            else if String.trim k.tresc == "" then
                                ( { s | kom = { k | blad = Just "Wpisz treść opinii.", info = Nothing } }, Cmd.none )

                            else
                                ( { s | kom = { k | wysylanie = True, blad = Nothing, info = Nothing } }
                                , wystawKomentarz s.token id (Maybe.withDefault 5 (String.toFloat k.ocena)) k.tresc
                                )
                )
                model

        OdpowiedzWystawienia (Ok ()) ->
            zSesja
                (\s ->
                    let
                        k =
                            s.kom
                    in
                    -- jeden przejazd to jedna opinia: auto znika z listy do oceny
                    ( { s
                        | kom = { k | wysylanie = False, tresc = "", info = Just "Dziękujemy za opinię." }
                        , doOceny = List.filter (\id -> Just id /= k.wybrany) s.doOceny
                        , zakonczony = if s.zakonczony == k.wybrany then Nothing else s.zakonczony
                      }
                    , case k.wybrany of
                        Just id ->
                            pobierzKomentarze s.token id

                        Nothing ->
                            Cmd.none
                    )
                )
                model

        OdpowiedzWystawienia (Err (Http.BadStatus 401)) ->
            sesjaWygasla model

        OdpowiedzWystawienia (Err blad) ->
            zSesja
                (\s ->
                    let
                        k =
                            s.kom
                    in
                    ( { s | kom = { k | wysylanie = False, blad = Just (opisBleduOpinii blad) } }, Cmd.none )
                )
                model


{-| zmienia coś w sesji tylko wtedy, gdy ktoś jest zalogowany; w innych stanach nic nie robi
-}
zSesja : (Sesja -> ( Sesja, Cmd Msg )) -> Model -> ( Model, Cmd Msg )
zSesja zmiana model =
    case model.stan of
        Zalogowany sesja ->
            let
                ( nowa, cmd ) =
                    zmiana sesja
            in
            ( { model | stan = Zalogowany nowa }, cmd )

        _ ->
            ( model, Cmd.none )


{-| backend odpowiedział 401: token nie działa, wracamy do logowania
-}
sesjaWygasla : Model -> ( Model, Cmd Msg )
sesjaWygasla model =
    ( doStronyGlownej (Formularz (Just "Sesja wygasła. Zaloguj się ponownie.")) model
    , Cmd.batch [ usunToken (), przewinDo "konto" ]
    )


naGore : Cmd Msg
naGore =
    Task.perform (\_ -> NicNieRob) (Browser.Dom.setViewport 0 0)


{-| Browser.Dom czeka na narysowanie widoku, więc sekcja już istnieje, gdy jej szukamy
-}
przewinDo : String -> Cmd Msg
przewinDo idSekcji =
    Browser.Dom.getElement idSekcji
        |> Task.andThen (\e -> Browser.Dom.setViewport 0 e.element.y)
        |> Task.attempt (\_ -> NicNieRob)


wybierzKierowce : String -> Sesja -> ( Sesja, Cmd Msg )
wybierzKierowce id s =
    let
        k =
            s.kom
    in
    if id == "" then
        ( { s | kom = { k | wybrany = Nothing, lista = ListaPusta, blad = Nothing, info = Nothing } }, Cmd.none )

    else
        ( { s | kom = { k | wybrany = Just id, lista = ListaLaduje, blad = Nothing, info = Nothing } }
        , pobierzKomentarze s.token id
        )


ustawPole : Pole -> String -> FormZamowienia -> FormZamowienia
ustawPole pole wartosc z =
    case pole of
        StartLat ->
            { z | startLat = wartosc }

        StartLon ->
            { z | startLon = wartosc }

        CelLat ->
            { z | celLat = wartosc }

        CelLon ->
            { z | celLon = wartosc }



-- VIEW


view : Model -> Html Msg
view model =
    case model.stan of
        Zalogowany sesja ->
            widokAplikacji model.flota sesja

        _ ->
            stronaGlowna model


