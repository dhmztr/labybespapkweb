module Mapa2D exposing (..)

import Html exposing (Html, div, text)
import Html.Attributes exposing (class, classList, style, title)
import Html.Events exposing (on)
import Json.Decode as D
import Types exposing (..)


-- mapa 2D: zapasowa, gdy przeglądarka nie ma WebGL


{-| zakres współrzędnych widoczny na mapie
-}
type alias Granice =
    { latMin : Float
    , latMax : Float
    , lonMin : Float
    , lonMax : Float
    }


{-| domyślnie okolice Wrocławia, ale auta błądzą losowo i z czasem odpływają,
więc zakres rozszerzamy tak, żeby zawsze mieściły się wszystkie auta i punkty
(zaokrąglony do 0,05°, żeby mapa nie "pływała" przy każdym ruchu auta)
-}
granice : List Kierowca -> List Znacznik -> Granice
granice kierowcy punkty =
    let
        szerokosci =
            51.0 :: 51.2 :: (List.map .lat kierowcy ++ List.map .lat punkty)

        dlugosci =
            16.85 :: 17.15 :: (List.map .lon kierowcy ++ List.map .lon punkty)

        dol x =
            toFloat (floor (x / 0.05)) * 0.05

        gora x =
            toFloat (ceiling (x / 0.05)) * 0.05
    in
    { latMin = dol (Maybe.withDefault 51.0 (List.minimum szerokosci))
    , latMax = gora (Maybe.withDefault 51.2 (List.maximum szerokosci))
    , lonMin = dol (Maybe.withDefault 16.85 (List.minimum dlugosci))
    , lonMax = gora (Maybe.withDefault 17.15 (List.maximum dlugosci))
    }




mapa : Bool -> List Kierowca -> List Znacznik -> Html Msg
mapa klikalna kierowcy punkty =
    let
        g =
            granice kierowcy punkty
    in
    div
        (class
            (if klikalna then
                "mapa klikalna"

             else
                "mapa"
            )
            :: (if klikalna then
                    [ on "click" (klikDekoder g) ]

                else
                    []
               )
        )
        (List.map (znacznikAuta g) kierowcy ++ List.map (znacznikPunktu g) punkty)


{-| pozycja kliknięcia w pikselach zamieniamy na współrzędne geograficzne;
znaczniki mają pointer-events: none, więc target to zawsze sama mapa
-}
klikDekoder : Granice -> D.Decoder Msg
klikDekoder g =
    D.map4
        (\x y szer wys ->
            KlikMapa
                (g.latMax - y / wys * (g.latMax - g.latMin))
                (g.lonMin + x / szer * (g.lonMax - g.lonMin))
        )
        (D.field "offsetX" D.float)
        (D.field "offsetY" D.float)
        (D.at [ "target", "offsetWidth" ] D.float)
        (D.at [ "target", "offsetHeight" ] D.float)


pozycja : Granice -> Float -> Float -> List (Html.Attribute Msg)
pozycja g lat lon =
    [ style "left" (procent ((lon - g.lonMin) / (g.lonMax - g.lonMin)))
    , style "top" (procent ((g.latMax - lat) / (g.latMax - g.latMin)))
    ]


procent : Float -> String
procent u =
    String.fromFloat (clamp 0 100 (u * 100)) ++ "%"


znacznikAuta : Granice -> Kierowca -> Html Msg
znacznikAuta g k =
    div
        (classList [ ( "auto", True ), ( "zajete", k.cel /= Nothing ) ]
            :: title ("Auto #" ++ k.id)
            :: pozycja g k.lat k.lon
        )
        [ text k.id ]


znacznikPunktu : Granice -> Znacznik -> Html Msg
znacznikPunktu g z =
    div (class ("punkt " ++ z.klasa) :: pozycja g z.lat z.lon) [ text z.napis ]
