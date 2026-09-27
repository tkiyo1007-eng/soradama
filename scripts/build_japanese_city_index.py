#!/usr/bin/env python3
"""Generate Soradama's offline Japanese municipality-prefix index.

Inputs are existing GeoNames dump/JP.zip and dump/alternatenames/JP.zip archives.
This script never downloads data, geocodes names, or invents coordinates/readings.
See JapaneseCityIndex-LICENSE.txt for attribution, selection rules and limits.
"""

import argparse
from collections import Counter, defaultdict
from dataclasses import dataclass
import hashlib
import json
from pathlib import Path
import re
from zipfile import ZipFile


JAPANESE = re.compile(r"[\u3040-\u30ff\u3400-\u9fff々〆ー]+")
MUNICIPALITY = re.compile(r"[\u3040-\u30ff\u3400-\u9fff々〆ー]+[市区町村]")
POPULATED_CODES = {"PPL", "PPLC", "PPLA", "PPLA2", "PPLA3", "PPLA4"}
ADMIN_CODES = {"ADM2", "ADM3", "ADM4"}
# Hamamatsu replaced these six wards on 2024-01-01; Tenryu remains valid.
# Official source: https://www.city.hamamatsu.shizuoka.jp/kikaku/kuseido/
# The downloaded GeoNames snapshot still marks them ADM3. Do not invent
# coordinates for their successors (Chuo/Hamana), which are absent here.
RETIRED_HAMAMATSU_WARDS = {1863291, 7418326, 7418329, 7506665, 7506666, 8739978}


@dataclass(frozen=True)
class Place:
    id: int
    name: str
    feature: str
    admin: tuple
    latitude: float
    longitude: float
    population: int


def archive_rows(path):
    with ZipFile(path) as archive:
        # Both country-specific exports call their data member JP.txt.
        for line in archive.read("JP.txt").decode("utf-8").splitlines():
            yield line.split("\t")


def read_places(path):
    places = {}
    for fields in archive_rows(path):
        if len(fields) != 19:
            raise ValueError("Unexpected GeoNames row width")
        if fields[8] != "JP":
            raise ValueError("Country export contains a non-Japanese record")
        place = Place(
            id=int(fields[0]), name=fields[1], feature=fields[7],
            admin=tuple(fields[10:14]), latitude=float(fields[4]),
            longitude=float(fields[5]), population=int(fields[14]),
        )
        if place.id in places or not (-90 <= place.latitude <= 90 and -180 <= place.longitude <= 180):
            raise ValueError("Duplicate identifier or invalid coordinates")
        places[place.id] = place
    return places


def read_names(path):
    names = defaultdict(lambda: defaultdict(list))
    for fields in archive_rows(path):
        if len(fields) != 10:
            raise ValueError("Expected alternateNamesV2's ten columns")
        # Exclude historic, colloquial and explicitly ended names. The source's
        # own classification is used; it cannot guarantee current legal status.
        if fields[2] not in {"ja", "en"} or fields[6] == "1" or fields[7] == "1" or fields[9]:
            continue
        value = fields[3]
        if fields[2] == "ja" and not JAPANESE.fullmatch(value):
            continue
        names[int(fields[1])][fields[2]].append((value, fields[4] == "1"))
    return names


def ordered_names(names, identifier, language):
    # Preferred first, then shortest, then lexical for reproducibility.
    values = names.get(identifier, {}).get(language, [])
    return [value for value, _ in sorted(set(values), key=lambda pair: (not pair[1], len(pair[0]), pair[0]))]


def japanese_name(place, names, municipality=False):
    values = ordered_names(names, place.id, "ja")
    if municipality:
        values = [value for value in values if MUNICIPALITY.fullmatch(value)]
    return values[0] if values else None


def english_name(place, names):
    values = ordered_names(names, place.id, "en")
    return values[0] if values else place.name


def is_inside(child, parent):
    level = int(parent.feature[-1])
    return child.admin[:level] == parent.admin[:level]


def build(places, names, acquired_date, sources):
    admin_lookup = {
        (place.feature, place.admin[:int(place.feature[-1])]): place
        for place in places.values() if place.feature in ADMIN_CODES | {"ADM1"}
    }
    populated_by_name = defaultdict(list)
    for place in places.values():
        if place.feature in POPULATED_CODES:
            for value in set(ordered_names(names, place.id, "ja")):
                populated_by_name[(place.admin[0], value)].append(place)

    entries = []
    skipped = []
    coordinates_from_population_center = 0
    qualified_names_assembled = []
    no_kana = []
    for administrative in sorted(places.values(), key=lambda place: place.id):
        if administrative.feature not in ADMIN_CODES:
            continue
        if administrative.id in RETIRED_HAMAMATSU_WARDS:
            skipped.append({"id": administrative.id, "name": administrative.name, "reason": "retiredHamamatsuWard20240101"})
            continue
        name = japanese_name(administrative, names, municipality=True)
        if not name:
            # Exclude counties (郡), unlabelled records and non-municipal areas.
            skipped.append({"id": administrative.id, "name": administrative.name, "reason": "noEligibleJapaneseMunicipalityName"})
            continue
        level = int(administrative.feature[-1])
        parents = [admin_lookup.get((f"ADM{depth}", administrative.admin[:depth])) for depth in range(1, level)]
        if not all(administrative.admin[:level]) or any(parent is None for parent in parents):
            skipped.append({"id": administrative.id, "name": administrative.name, "reason": "incompleteAdministrativeHierarchy"})
            continue
        prefecture = parents[0]
        prefecture_name = japanese_name(prefecture, names)
        if not prefecture_name:
            skipped.append({"id": administrative.id, "name": administrative.name, "reason": "noJapanesePrefectureName"})
            continue

        # Match a real population center only by verified administrative codes
        # and the same Japanese name, optionally without its municipal suffix.
        matching = {}
        # A ward stem may equal its parent city (堺区 -> 堺). Do not assign the
        # city's population center to a ward just because that center is in it.
        matching_spellings = (name,) if name.endswith("区") else (name, name[:-1])
        for spelling in matching_spellings:
            for candidate in populated_by_name[(administrative.admin[0], spelling)]:
                if is_inside(candidate, administrative):
                    matching[candidate.id] = candidate
        representative = min(matching.values(), key=lambda place: (
            place.feature == "PPL", -place.population, place.id
        )) if matching else administrative
        coordinates_from_population_center += representative.id != administrative.id

        aliases = set(ordered_names(names, administrative.id, "ja"))
        aliases.update(ordered_names(names, representative.id, "ja"))
        name_en = english_name(representative, names)
        # City wards have names shared by other cities in the same prefecture.
        # Qualify using a source alias, or the verified parent + ward labels.
        # This is formatting of the source hierarchy, not a guessed place name.
        if name.endswith("区") and level > 2:
            parent_city = next((parent for parent in reversed(parents[1:])
                                if (japanese_name(parent, names, True) or "").endswith("市")), None)
            if parent_city:
                parent_name = japanese_name(parent_city, names, True)
                if not name.startswith(parent_name):
                    qualified = parent_name + name
                    if qualified not in aliases:
                        qualified_names_assembled.append(administrative.id)
                    aliases.add(qualified)
                    name = qualified
                name_en = f"{english_name(parent_city, names)} / {name_en}"
        aliases.add(name)
        if not any(re.fullmatch(r"[\u3041-\u3096\u30a1-\u30faー]+", alias) for alias in aliases):
            no_kana.append(administrative.id)
        entries.append({
            "id": representative.id,
            "name": name,
            "nameEn": name_en,
            "aliases": sorted(aliases),
            "prefecture": prefecture_name,
            "prefectureEn": english_name(prefecture, names),
            "latitude": representative.latitude,
            "longitude": representative.longitude,
            "population": representative.population,
        })

    entries.sort(key=lambda entry: (entry["prefecture"], entry["name"], entry["id"]))
    ids = [entry["id"] for entry in entries]
    labels = [(entry["prefecture"], entry["name"]) for entry in entries]
    if len(set(ids)) != len(ids) or len(set(labels)) != len(labels):
        duplicate_ids = [value for value, count in Counter(ids).items() if count > 1]
        duplicate_labels = [value for value, count in Counter(labels).items() if count > 1]
        raise ValueError(f"Duplicate representatives {duplicate_ids}; ambiguous labels {duplicate_labels}")
    metadata = {
        "schemaVersion": 1,
        "acquiredDate": acquired_date,
        "sources": sources,
        "license": "CC BY 4.0",
        "attribution": "GeoNames (https://www.geonames.org/)",
        "selection": "Japanese non-historic ADM2/ADM3/ADM4 municipalities with complete administrative hierarchy; matching population centers preferred",
        "entryCount": len(entries),
        "prefectureCount": len({entry["prefecture"] for entry in entries}),
        "populationCenterCount": coordinates_from_population_center,
        "entriesWithoutKana": no_kana,
        "hierarchyQualifiedNameIDs": qualified_names_assembled,
        "excludedReasonCounts": dict(sorted(Counter(item["reason"] for item in skipped).items())),
    }
    return {"metadata": metadata, "entries": entries}, skipped


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--places", required=True, type=Path)
    parser.add_argument("--alternate-names", required=True, type=Path)
    parser.add_argument("--acquired-date", required=True, help="Actual download date, YYYY-MM-DD")
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", args.acquired_date):
        parser.error("Expected acquired date in YYYY-MM-DD format")
    sources = [
        {"url": "https://download.geonames.org/export/dump/JP.zip", "sha256": hashlib.sha256(args.places.read_bytes()).hexdigest()},
        {"url": "https://download.geonames.org/export/dump/alternatenames/JP.zip", "sha256": hashlib.sha256(args.alternate_names.read_bytes()).hexdigest()},
    ]
    index, skipped = build(read_places(args.places), read_names(args.alternate_names), args.acquired_date, sources)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(index, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(index["metadata"], ensure_ascii=False, indent=2))
    print("Excluded administrative records:")
    for item in skipped:
        # Public source names only; no user data is read by this generator.
        print(json.dumps(item, ensure_ascii=False))


if __name__ == "__main__":
    main()
