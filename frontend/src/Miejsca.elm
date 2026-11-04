module Miejsca exposing (..)

import Html exposing (img)
import Types exposing (..)
import Format exposing (aut, wolneAuta, wolnychAut)


-- MIEJSCA NA TAŚMIE W NAGŁÓWKU


type alias Miejsce =
    { nazwa : String
    , lat : Float
    , lon : Float
    , zdjecie : String
    , szer : Int
    , wys : Int
    , opis : String
    }


miejscaNaTasmie : List Miejsce
miejscaNaTasmie =
    [ Miejsce "Dworzec Główny" 51.0981 17.0365 "img/dworzec.jpg" 1920 1221 "Pusty peron pod stalowym dachem Dworca Głównego nocą"
    , Miejsce "Rynek" 51.11 17.032 "img/rynek.jpg" 1920 1162 "Dorożka z pasażerami na bruku wrocławskiego Rynku"
    , Miejsce "Most Młyński" 51.1155 17.042 "img/most-mlynski.jpg" 1920 1185 "Kratownice Mostu Młyńskiego we mgle przed świtem"
    , Miejsce "Muzeum Narodowe" 51.1104 17.047 "img/muzeum.jpg" 1920 1343 "Ceglany gmach Muzeum Narodowego odbity nocą w Odrze"
    ]


odlegloscKm : Float -> Float -> Float -> Float -> Float
odlegloscKm lat1 lon1 lat2 lon2 =
    let
        dy =
            (lat1 - lat2) * 111.2

        dx =
            (lon1 - lon2) * 111.2 * cos (degrees ((lat1 + lat2) / 2))
    in
    sqrt (dx * dx + dy * dy)





wPoblizu : List Kierowca -> Miejsce -> String
wPoblizu flota m =
    let
        n =
            List.length (List.filter (\k -> odlegloscKm k.lat k.lon m.lat m.lon <= 2) (wolneAuta flota))
    in
    if List.isEmpty flota then
        "łączenie z flotą…"

    else if n == 0 then
        "brak wolnych aut w promieniu 2 km"

    else
        wolnychAut n ++ " w promieniu 2 km"
