module UrlParsing exposing (parseSelectionsFromUrl, setSelectionsInUrl)

import Api.Types as Api
import Data exposing (..)
import Url
import Url.Parser
import Url.Parser.Query


parseSelectionsFromUrl : Url.Url -> List Selection
parseSelectionsFromUrl url =
    -- To avoid having to deal with path parsing, remove the path.
    { url | path = "/" }
        |> Url.Parser.parse selectionsUrlParser
        |> Maybe.withDefault []


selectionsUrlParser : Url.Parser.Parser (List Selection -> a) a
selectionsUrlParser =
    Url.Parser.query selectionsQueryParser


selectionsQueryParser : Url.Parser.Query.Parser (List Selection)
selectionsQueryParser =
    Url.Parser.Query.custom "stop" (List.filterMap parseSelection)


parseSelection : String -> Maybe Selection
parseSelection queryValue =
    case String.split "," queryValue of
        [ routeId, stopId ] ->
            Just
                { routeId = Api.RouteId routeId
                , stopId = Api.StopId stopId
                , directionId = Nothing
                }

        [ routeId, stopId, "0" ] ->
            Just
                { routeId = Api.RouteId routeId
                , stopId = Api.StopId stopId
                , directionId = Just Api.D0
                }

        [ routeId, stopId, "1" ] ->
            Just
                { routeId = Api.RouteId routeId
                , stopId = Api.StopId stopId
                , directionId = Just Api.D1
                }

        _ ->
            Nothing


setSelectionsInUrl : List Selection -> Url.Url -> Url.Url
setSelectionsInUrl selections url =
    let
        queryParams =
            selections
                |> List.map encodeSelectionAsQueryParam
                |> String.join "&"
    in
    { url | query = Just queryParams }


encodeSelectionAsQueryParam : Selection -> String
encodeSelectionAsQueryParam selection =
    let
        (Api.RouteId routeId) =
            selection.routeId

        (Api.StopId stopId) =
            selection.stopId

        directionId =
            case selection.directionId of
                Nothing ->
                    ""

                Just Api.D0 ->
                    ",0"

                Just Api.D1 ->
                    ",1"
    in
    String.concat
        [ "stop="
        , routeId
        , ","
        , stopId
        , directionId
        ]
