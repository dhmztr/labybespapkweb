module Format exposing (..)

import Html exposing (Html)
import Html.Attributes exposing (attribute)
import Types exposing (..)


{-| akceptuje i kropkę, i przecinek: "51,1" i "51.1"
-}
parsuj : String -> Maybe Float
parsuj tekst =
    String.toFloat (String.replace "," "." (String.trim tekst))


numerAuta : Kierowca -> Int
numerAuta k =
    Maybe.withDefault 0 (String.toInt k.id)


zaokr4 : Float -> String
zaokr4 x =
    String.fromFloat (toFloat (round (x * 10000)) / 10000)



-- ODMIANA


kilka : Int -> Bool
kilka n =
    modBy 10 n >= 2 && modBy 10 n <= 4 && (modBy 100 n < 12 || modBy 100 n > 14)


aut : Int -> String
aut n =
    String.fromInt n
        ++ (if n == 1 then
                " auto"

            else if kilka n then
                " auta"

            else
                " aut"
           )


wolnychAut : Int -> String
wolnychAut n =
    String.fromInt n
        ++ (if n == 1 then
                " wolne auto"

            else if kilka n then
                " wolne auta"

            else
                " wolnych aut"
           )


miejsc : Int -> String
miejsc n =
    String.fromInt n
        ++ (if n == 1 then
                " miejsce"

            else if kilka n then
                " miejsca"

            else
                " miejsc"
           )


osob : Int -> String
osob n =
    String.fromInt n
        ++ (if n == 1 then
                " osoba"

            else if kilka n then
                " osoby"

            else
                " osób"
           )


jednoMiejsce : Float -> String
jednoMiejsce x =
    String.replace "." "," (String.fromFloat (toFloat (round (x * 10)) / 10))


stanFloty : List Kierowca -> String
stanFloty flota =
    if List.isEmpty flota then
        "Łączenie z flotą…"

    else
        aut (List.length flota) ++ " w mieście, wolne: " ++ String.fromInt (List.length (wolneAuta flota))


wolneAuta : List Kierowca -> List Kierowca
wolneAuta =
    List.filter (\k -> k.cel == Nothing)


wejscie : Int -> List (Html.Attribute Msg)
wejscie krok =
    [ attribute "data-wejdz" "", attribute "data-krok" (String.fromInt krok) ]
