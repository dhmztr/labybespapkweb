module View.Strona exposing (..)

import Html exposing (Html, a, button, dd, details, div, dl, dt, figcaption, figure, footer, h1, h2, h3, header, img, input, label, li, nav, node, p, section, span, summary, text, ul)
import Html.Attributes exposing (alt, attribute, autocomplete, class, height, href, id, maxlength, spellcheck, src, style, type_, value, width)
import Html.Events exposing (onClick, onInput)
import Types exposing (..)
import Klasy exposing (klasaDla, komfort, parsujPytanie)
import Format exposing (aut, jednoMiejsce, miejsc, osob, stanFloty, wejscie, wolneAuta)
import Miejsca exposing (Miejsce, miejscaNaTasmie, odlegloscKm, wPoblizu)
import Mapa3D exposing (auto3d, flotaJson)
import Mapa2D exposing (mapa)
import View.Konto exposing (sekcjaKonto)






-- strona główna


stronaGlowna : Model -> Html Msg
stronaGlowna model =
    div [ class "strona" ]
        [ hero model.flota
        , sekcjaFlota model
        , sekcjaJak
        , sekcjaPytania
        , sekcjaKonto model
        , stopka
        ]


hero : List Kierowca -> Html Msg
hero flota =
    section [ id "hero", class "hero" ]
        [ div [ class "hero__scena" ]
            [ header [ class "pasek" ]
                [ a [ class "znak", href "#hero" ] [ text "unter" ]
                , nav [ class "pasek__linki", attribute "aria-label" "Strona główna" ]
                    [ a [ class "pasek__link", href "#flota" ] [ text "Flota" ]
                    , a [ class "pasek__link", href "#jak" ] [ text "Jak to działa" ]
                    , a [ class "pasek__link", href "#pytania" ] [ text "Pytania" ]
                    , a [ class "pasek__link", href repozytorium ] [ text "GitHub" ]
                    , a [ class "przycisk przycisk--maly", href "#konto" ] [ text "Zaloguj się" ]
                    ]
                ]
            , h1 [ class "hero__zdanie" ]
                [ span [ class "pol pol--lewa" ] [ text "Przejazdy" ]
                , text " "
                , span [ class "pol pol--prawa" ] [ text "po Wrocławiu" ]
                ]
            , div [ class "tasma" ]
                (figure [ class "kadr kadr--miasto" ]
                    [ node "unter-miasto"
                        [ class "kadr__miasto"
                        , attribute "tryb" "podglad"
                        , attribute "auta" (flotaJson flota)
                        , attribute "role" "img"
                        , attribute "aria-label" "Mapa 3D Wrocławia z autami Unter w ich obecnych pozycjach"
                        ]
                        []
                    , figcaption [ class "kadr__podpis" ] [ text "Flota Unter na żywo" ]
                    ]
                    :: List.map (kadrMiejsca flota) miejscaNaTasmie
                )
            , div [ class "hero__opis" ]
                [ p [ class "hero__zdanie-pomocnicze" ]
                    [ text "Wskazujesz start i cel na mapie, a Unter wysyła najbliższe wolne auto, w którym zmieścicie się wszyscy." ]
                , div [ class "hero__akcja" ]
                    [ a [ class "przycisk", href "#konto" ] [ text "Zamów przejazd" ]
                    , p [ class "hero__na-zywo", attribute "aria-live" "polite" ] [ text (stanFloty flota) ]
                    ]
                ]
            ]
        ]


kadrMiejsca : List Kierowca -> Miejsce -> Html Msg
kadrMiejsca flota m =
    figure [ class "kadr" ]
        [ img [ src m.zdjecie, alt m.opis, width m.szer, height m.wys, attribute "decoding" "async" ] []
        , figcaption [ class "kadr__podpis" ] [ text (m.nazwa ++ " · " ++ wPoblizu flota m) ]
        ]


sekcjaFlota : Model -> Html Msg
sekcjaFlota model =
    let
        wynik =
            parsujPytanie model.pytanie

        ( osoby, klasa ) =
            case wynik of
                Just ( n, bagaz ) ->
                    ( n, klasaDla (min n 4) bagaz )

                Nothing ->
                    ( 3, komfort )

        pasujace =
            List.filter (\k -> k.wolne >= max (min osoby 4) klasa.miejsca) (wolneAuta model.flota)

        rynek =
            { lat = 51.11, lon = 17.032 }

        najblizsze =
            pasujace
                |> List.map (\k -> ( k, odlegloscKm k.lat k.lon rynek.lat rynek.lon ))
                |> List.sortBy Tuple.second
                |> List.head

        uwaga =
            case wynik of
                Nothing ->
                    Just "Napisz, ile osób jedzie, na przykład „we dwoje”. Na razie pokazujemy Komfort."

                Just ( n, _ ) ->
                    if n > 4 then
                        Just "Jedno zamówienie to najwyżej 4 osoby. Przy większej grupie zamówcie dwa auta."

                    else
                        Nothing
    in
    section [ id "flota", class "sekcja flota" ]
        [ h2 (id "flota-tytul" :: class "flota__tytul" :: wejscie 0) [ text "Ile was jedzie?" ]
        , input
            ([ id "pytanie"
             , class "flota__pole"
             , attribute "data-ui" ""
             , attribute "aria-labelledby" "flota-tytul"
             , type_ "text"
             , value model.pytanie
             , onInput WpisanoPytanie
             , spellcheck False
             , autocomplete False
             , maxlength 60
             ]
                ++ wejscie 1
            )
            []
        , div [ class "flota__uklad" ]
            [ div (class "flota__lewa" :: wejscie 2)
                [ div [ class "odpowiedz", attribute "data-ui" "", attribute "aria-live" "polite" ]
                    [ h3 [ class "odpowiedz__klasa" ] [ text klasa.nazwa ]
                    , p [ class "odpowiedz__opis" ] [ text klasa.opis ]
                    , dl [ class "dane" ]
                        [ div [ class "dane__wiersz" ]
                            [ dt [] [ text "Jedzie" ]
                            , dd [] [ text (osob osoby) ]
                            ]
                        , div [ class "dane__wiersz" ]
                            [ dt [] [ text "Wolne miejsca w aucie" ]
                            , dd [] [ text (String.fromInt klasa.miejsca) ]
                            ]
                        , div [ class "dane__wiersz" ]
                            [ dt [] [ text "Pasujących wolnych aut teraz" ]
                            , dd []
                                [ text
                                    (if List.isEmpty model.flota then
                                        "…"

                                     else
                                        String.fromInt (List.length pasujace)
                                    )
                                ]
                            ]
                        , div [ class "dane__wiersz" ]
                            [ dt [] [ text "Najbliżej Rynku" ]
                            , dd []
                                [ text
                                    (case najblizsze of
                                        Just ( k, km ) ->
                                            "#" ++ k.id ++ " · " ++ jednoMiejsce km ++ " km"

                                        Nothing ->
                                            "brak"
                                    )
                                ]
                            ]
                        ]
                    , case uwaga of
                        Just tresc ->
                            p [ class "odpowiedz__uwaga" ] [ text tresc ]

                        Nothing ->
                            text ""
                    ]
                , div [ class "przyklady" ]
                    (List.map
                        (\t -> button [ type_ "button", class "przyklad", onClick (WpisanoPytanie t) ] [ text t ])
                        [ "jadę sam", "we dwoje", "nas jest troje", "czworo z walizkami" ]
                    )
                ]
            , div (class "flota__scena" :: wejscie 3)
                [ auto3d "flota__auto" klasa True ]
            ]
        ]


type alias Etap =
    { czas : String
    , opis : String
    , waga : Int
    , kolor : String
    }


sekcjaJak : Html Msg
sekcjaJak =
    section [ id "jak", class "sekcja jak" ]
        [ h2 (class "jak__tytul" :: wejscie 0) [ text "Od kliknięcia do celu" ]
        , div (class "pasmo" :: attribute "data-ui" "" :: wejscie 1)
            (List.map etap
                [ Etap "Kilka sekund" "Najpierw wskazujesz na mapie start i cel, i liczbę osób." 6 "granat"
                , Etap "Od razu" "Potem Unter wybiera najbliższe wolne auto z miejscem dla was." 1 "czern"
                , Etap "Kilkanaście sekund" "Wtedy auto podjeżdża po was i wiezie do celu, a mapa pokazuje je co 2 sekundy." 20 "popiel"
                , Etap "Około minuty" "Na koniec, po dojechaniu, oceniasz kierowcę od 1 do 5 gwiazdek." 24 "kamien"
                ]
            )
        ]


etap : Etap -> Html Msg
etap e =
    div [ class "etap", style "flex-grow" (String.fromInt e.waga) ]
        [ div [ class ("etap__pole etap__pole--" ++ e.kolor) ] [ p [ class "etap__czas" ] [ text e.czas ] ]
        , p [ class "etap__opis" ] [ text e.opis ]
        ]


sekcjaPytania : Html Msg
sekcjaPytania =
    section [ id "pytania", class "sekcja pytania" ]
        [ h2 (class "pytania__tytul" :: wejscie 0) [ text "Zanim zamówisz" ]
        , ul (class "pytania__lista" :: wejscie 1)
            (List.map wierszPytania
                [ ( "Ile osób zmieści jedno zamówienie?", "Od jednej do czterech. Unter bierze pod uwagę tylko auta, które mają tyle wolnych miejsc." )
                , ( "Jak Unter wybiera auto?", "Spośród wolnych aut z wystarczającą liczbą miejsc wysyła to, które stoi najbliżej punktu startu." )
                , ( "Czy mogę zamówić dwa przejazdy naraz?", "Nie. Trwający przejazd widać w aplikacji na każdej zakładce, a kolejny zamówisz, gdy ten się zakończy." )
                , ( "Dlaczego czasem muszę chwilę poczekać?", "Logowanie, rejestracja, zamówienie i opinia mają wspólny limit kilku prób na 10 sekund z jednego adresu. To ochrona przed spamem." )
                , ( "Kto widzi moją opinię?", "Wszyscy zalogowani. Zamiast całego adresu e-mail pokazujemy tylko jego pierwszą literę i domenę." )
                , ( "Kiedy mogę ocenić kierowcę?", "Po zakończonym przejeździe. Aplikacja sama zaproponuje opinię, gdy auto dowiezie was do celu." )
                ]
            )
        ]


wierszPytania : ( String, String ) -> Html Msg
wierszPytania ( q, odp ) =
    li [ class "pytanie" ]
        [ details []
            [ summary [ class "pytanie__tresc" ] [ text q ]
            , p [ class "pytanie__odpowiedz" ] [ text odp ]
            ]
        ]




{-| kod projektu, linkowany w pasku i w stopce strony głównej
-}
repozytorium : String
repozytorium =
    "https://github.com/dhmztr/labybespapkweb"


stopka : Html Msg
stopka =
    footer [ class "stopka" ]
        [ div [ class "stopka__gora" ]
            [ div [ class "stopka__zaproszenie" ]
                [ h2 [ class "stopka__tytul" ] [ text "Gdzie dziś jedziesz?" ]
                , a [ class "przycisk", href "#konto" ] [ text "Zamów przejazd" ]
                ]
            , ul [ class "stopka__linki" ]
                [ li [] [ a [ href "#flota" ] [ text "Flota" ] ]
                , li [] [ a [ href "#jak" ] [ text "Jak to działa" ] ]
                , li [] [ a [ href "#pytania" ] [ text "Pytania" ] ]
                , li [] [ a [ href "/swagger-ui" ] [ text "Dokumentacja API" ] ]
                , li [] [ a [ href repozytorium ] [ text "Kod na GitHubie" ] ]
                ]
            ]
        , div [ class "stopka__dol" ]
            [ p [ class "stopka__zrodla" ]
                [ text "Zdjęcia: "
                , zrodlo "https://commons.wikimedia.org/wiki/File:Breslau-People-16-Rynek-Droschke-2014-gje.jpg" "Rynek" "Gerd Eichmann" "https://creativecommons.org/licenses/by/4.0" "CC BY 4.0"
                , text "; "
                , zrodlo "https://commons.wikimedia.org/wiki/File:Wroclaw_Most_Mlynski_w_porannej_mgle_przed_switem.jpg" "Most Młyński" "Jar.ciurus" "https://creativecommons.org/licenses/by-sa/3.0/pl/deed.en" "CC BY-SA 3.0"
                , text "; "
                , zrodlo "https://commons.wikimedia.org/wiki/File:Wroc%C5%82aw_G%C5%82%C3%B3wny_(Breslau_Hauptbahnhof)_by_night.JPG" "Dworzec Główny" "Pudelek (Marcin Szala)" "https://creativecommons.org/licenses/by-sa/4.0" "CC BY-SA 4.0"
                , text "; "
                , zrodlo "https://commons.wikimedia.org/wiki/File:Wroc%C5%82aw_MuzeumNarodowe.jpg" "Muzeum Narodowe" "Marek Śliwecki" "https://creativecommons.org/licenses/by-sa/4.0" "CC BY-SA 4.0"
                , text "; wszystkie przez Wikimedia Commons. Mapa: Esri, HERE, Garmin, © "
                , a [ href "https://www.openstreetmap.org/copyright" ] [ text "OpenStreetMap" ]
                , text "."
                ]
            , p [ class "stopka__projekt" ] [ text "Unter, projekt studencki · Wrocław 2026" ]
            ]
        , p [ class "stopka__nazwa", attribute "aria-hidden" "true" ] [ text "unter" ]
        ]


zrodlo : String -> String -> String -> String -> String -> Html Msg
zrodlo strona nazwa autor licencjaUrl licencja =
    span []
        [ a [ href strona ] [ text nazwa ]
        , text (", " ++ autor ++ ", ")
        , a [ href licencjaUrl ] [ text licencja ]
        ]
