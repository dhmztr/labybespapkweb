module Klasy exposing (..)

import Types exposing (..)


-- KLASY AUT
-- backend zna tylko liczbę wolnych miejsc, więc to ona wyznacza klasę i model 3D auta


type alias Klasa =
    { kod : String
    , nazwa : String
    , miejsca : Int
    , opis : String
    }


mini : Klasa
mini =
    Klasa "mini" "Mini" 2 "Mały biały hatchback na dwie osoby. Zmieści się w każdej uliczce Starego Miasta."


komfort : Klasa
komfort =
    Klasa "komfort" "Komfort" 3 "Granatowy sedan na trzy osoby. Spokojny kurs przez całe miasto."


kombi : Klasa
kombi =
    Klasa "kombi" "Kombi" 4 "Grafitowe kombi na cztery osoby i duży bagażnik."


xl : Klasa
xl =
    Klasa "xl" "XL" 5 "Jasny van z pięcioma miejscami, gdy jedzie was czworo z bagażami."


klasaAuta : Kierowca -> Klasa
klasaAuta k =
    if k.wolne <= 2 then
        mini

    else if k.wolne == 3 then
        komfort

    else if k.wolne == 4 then
        kombi

    else
        xl


{-| najmniejsza klasa, w której zmieści się tyle osób; bagaż podbija o jedną klasę
-}
klasaDla : Int -> Bool -> Klasa
klasaDla osoby bagaz =
    let
        podstawowa =
            if osoby <= 2 then
                0

            else
                osoby - 2

        poziom =
            if bagaz then
                podstawowa + 1

            else
                podstawowa
    in
    case poziom of
        0 ->
            mini

        1 ->
            komfort

        2 ->
            kombi

        _ ->
            xl


{-| "nas jest troje" -> 3 osoby, "czworo z walizkami" -> 4 osoby i bagaż
-}
parsujPytanie : String -> Maybe ( Int, Bool )
parsujPytanie tekst =
    let
        t =
            String.toLower tekst

        ma slowa =
            List.any (\s -> String.contains s t) slowa

        bagaz =
            ma [ "walizk", "bagaż", "bagaz", "rower", "narty", "plecak" ]

        osoby =
            if ma [ "5", "6", "7", "8", "pięć", "piec", "pięcio", "piecio", "sześć", "szesc" ] then
                Just 5

            else if ma [ "4", "czter", "czworo", "czwórk", "czwork" ] then
                Just 4

            else if ma [ "3", "trzy", "trzech", "troje", "trójk", "trojk" ] then
                Just 3

            else if ma [ "2", "dwa", "dwie", "dwoje", "dwóch", "dwoch", "para", "z żoną", "z mężem", "z kimś" ] then
                Just 2

            else if ma [ "1", "sam", "jeden", "jedna", "solo" ] then
                Just 1

            else
                Nothing
    in
    Maybe.map (\n -> ( n, bagaz )) osoby
