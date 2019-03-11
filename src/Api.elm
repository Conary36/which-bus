port module Api exposing
    ( ApiData
    , ApiResult(..)
    , Error(..)
    , Msg
    , init
    , makeUrl
    , predictionsForSelection
    , subscriptions
    , update
    )

import AssocList as Dict
import Data exposing (..)
import Iso8601
import Json.Decode as Decode
import Json.Decode.Pipeline as Pipeline
import Json.Encode
import Time


port startStreamPort : String -> Cmd msg


port streamEventPort : (Decode.Value -> msg) -> Sub msg


type ApiResult
    = Loading
    | Failure Error
    | Success ApiData


type Error
    = DecodeError Decode.Error
    | BadOrder String


type alias ApiData =
    { predictions : Dict.Dict PredictionId Prediction
    , trips : Dict.Dict TripId Trip
    }


type alias Msg =
    Result Decode.Error StreamEvent


type StreamEvent
    = Reset (List Resource)
    | Insert Resource
    | Remove ResourceId


type ResourceId
    = ResourcePredictionId PredictionId
    | ResourceTripId TripId


type Resource
    = ResourcePrediction Prediction
    | ResourceTrip Trip


type PredictionId
    = PredictionId String


type alias Prediction =
    { id : PredictionId
    , time : Time.Posix
    , selection : Selection
    , tripId : TripId
    }


type TripId
    = TripId String


type alias Trip =
    { id : TripId
    , headsign : String
    }


makeUrl : String -> List ( String, String ) -> String
makeUrl path params =
    let
        base =
            "https://api-v3.mbta.com/"

        apiKey =
            "3a6d67c08111426d8617a30340a9fad3"

        paramsWithKey =
            ( "api_key", apiKey ) :: params
    in
    String.concat
        [ base
        , path
        , "?"
        , paramsWithKey
            |> List.map (\( param, value ) -> param ++ "=" ++ value)
            |> String.join "&"
        ]


init : List Selection -> ( ApiResult, Cmd msg )
init selections =
    ( Loading
    , startStream selections
    )


emptyData : ApiData
emptyData =
    { predictions = Dict.empty
    , trips = Dict.empty
    }


startStream : List Selection -> Cmd msg
startStream selections =
    let
        routeIds =
            selections
                |> List.map .routeId
                |> List.map (\(RouteId routeId) -> routeId)
                |> String.join ","

        stopIds =
            selections
                |> List.map .stopId
                |> List.map (\(StopId stopId) -> stopId)
                |> String.join ","

        url =
            makeUrl
                "predictions"
                [ ( "filter[route]", routeIds )
                , ( "filter[stop]", stopIds )
                , ( "include", "trip" )
                ]
    in
    startStreamPort url


subscriptions : (Msg -> msg) -> Sub msg
subscriptions msg =
    streamEventPort (Decode.decodeValue streamEventDecoder >> msg)


update : Msg -> ApiResult -> ApiResult
update eventDecodeResult apiResult =
    case ( eventDecodeResult, apiResult ) of
        ( _, Failure error ) ->
            Failure error

        ( Err decodeError, _ ) ->
            Failure (DecodeError decodeError)

        ( Ok (Reset newResources), _ ) ->
            Success <|
                List.foldl insertResource emptyData newResources

        ( Ok (Insert _), Loading ) ->
            Failure (BadOrder "Insert while Loading")

        ( Ok (Remove _), Loading ) ->
            Failure (BadOrder "Remove while Loading")

        ( Ok (Insert newResource), Success apiData ) ->
            Success <|
                insertResource newResource apiData

        ( Ok (Remove resourceId), Success apiData ) ->
            case resourceId of
                ResourcePredictionId predictionId ->
                    if Dict.member predictionId apiData.predictions then
                        Success <|
                            { apiData
                                | predictions =
                                    Dict.remove predictionId apiData.predictions
                            }

                    else
                        Failure (BadOrder "Remove unknown prediction id")

                ResourceTripId tripId ->
                    if Dict.member tripId apiData.trips then
                        Success <|
                            { apiData
                                | trips =
                                    Dict.remove tripId apiData.trips
                            }

                    else
                        Failure (BadOrder "Remove unknown trip id")


insertResource : Resource -> ApiData -> ApiData
insertResource resource apiData =
    case resource of
        ResourcePrediction prediction ->
            { apiData
                | predictions =
                    Dict.insert prediction.id prediction apiData.predictions
            }

        ResourceTrip trip ->
            { apiData
                | trips =
                    Dict.insert trip.id trip apiData.trips
            }


predictionsForSelection : Selection -> ApiData -> List ShownPrediction
predictionsForSelection selection apiData =
    apiData.predictions
        |> Dict.values
        |> List.filter (\prediction -> prediction.selection == selection)
        |> List.map
            (\prediction ->
                { time = prediction.time
                , tripHeadsign =
                    apiData.trips
                        |> Dict.get prediction.tripId
                        |> Maybe.map .headsign
                }
            )



-- Decoding / Encoding


encodeSelection : Selection -> Json.Encode.Value
encodeSelection selection =
    let
        (RouteId routeId) =
            selection.routeId

        (StopId stopId) =
            selection.stopId
    in
    Json.Encode.object
        [ ( "route_id", Json.Encode.string routeId )
        , ( "stop_id", Json.Encode.string stopId )
        ]


streamEventDecoder : Decode.Decoder StreamEvent
streamEventDecoder =
    Decode.field "event" Decode.string
        |> Decode.andThen
            (\eventName ->
                Decode.field "data" (eventDataDecoder eventName)
            )


eventDataDecoder : String -> Decode.Decoder StreamEvent
eventDataDecoder eventName =
    case eventName of
        "reset" ->
            Decode.map Reset (Decode.list resourceDecoder)

        "add" ->
            Decode.map Insert resourceDecoder

        "update" ->
            Decode.map Insert resourceDecoder

        "remove" ->
            Decode.map Remove resourceIdDecoder

        _ ->
            Decode.fail ("unrecognized event name " ++ eventName)


resourceIdDecoder : Decode.Decoder ResourceId
resourceIdDecoder =
    Decode.map2
        Tuple.pair
        (Decode.at [ "type" ] Decode.string)
        (Decode.at [ "id" ] Decode.string)
        |> Decode.andThen
            (\( typeString, id ) ->
                case typeString of
                    "prediction" ->
                        Decode.succeed (ResourcePredictionId (PredictionId id))

                    "trip" ->
                        Decode.succeed (ResourceTripId (TripId id))

                    otherType ->
                        Decode.fail ("unrecognized type " ++ otherType)
            )


resourceDecoder : Decode.Decoder Resource
resourceDecoder =
    Decode.at [ "type" ] Decode.string
        |> Decode.andThen
            (\typeString ->
                case typeString of
                    "prediction" ->
                        Decode.map ResourcePrediction predictionDecoder

                    "trip" ->
                        Decode.map ResourceTrip tripDecoder

                    otherType ->
                        Decode.fail ("unrecognized type " ++ otherType)
            )


predictionDecoder : Decode.Decoder Prediction
predictionDecoder =
    Decode.succeed Prediction
        |> Pipeline.required "id" (Decode.map PredictionId Decode.string)
        |> Pipeline.custom
            (Decode.oneOf
                [ Decode.at [ "attributes", "arrival_time" ] Iso8601.decoder
                , Decode.at [ "attributes", "departure_time" ] Iso8601.decoder
                ]
            )
        |> Pipeline.custom
            (Decode.succeed Selection
                |> Pipeline.requiredAt [ "relationships", "route", "data", "id" ] (Decode.map RouteId Decode.string)
                |> Pipeline.requiredAt [ "relationships", "stop", "data", "id" ] (Decode.map StopId Decode.string)
            )
        |> Pipeline.requiredAt [ "relationships", "trip", "data", "id" ] (Decode.map TripId Decode.string)


tripDecoder : Decode.Decoder Trip
tripDecoder =
    Decode.succeed Trip
        |> Pipeline.required "id" (Decode.map TripId Decode.string)
        |> Pipeline.requiredAt [ "attributes", "headsign" ] Decode.string
