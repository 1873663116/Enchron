from __future__ import annotations

from pathlib import Path
import re
from typing import Any, Dict, FrozenSet, Iterable, Mapping, Optional, Sequence, Tuple

from .applicability import parse_applicability, referenced_facts
from .contracts import (
    ArgumentField,
    ArgumentRule,
    ArgumentRuleCase,
    ArgumentSchema,
    ArgumentValueKind,
    ArtifactClass,
    AutomationScope,
    BoundLane,
    ContractBlocker,
    ContractReadiness,
    DraftCatalog,
    EvidenceSchemaPair,
    EvidenceObligation,
    FactDeclaration,
    JourneyContract,
    HumanCoverageBlocker,
    ImplementationGapBlocker,
    LaneRequirement,
    OperationCall,
    OperationContract,
    OperationRole,
    OracleContract,
    OracleKind,
    PreparationContract,
    PromiseContract,
    RubricContract,
    ScenarioContract,
    StateDeclaration,
    StateRequirement,
)
from .errors import RegressionError
from .expression import parse_success_expression, validate_expression_obligations
from .frontmatter import FrontMatterDocument, load_frontmatter
from .ids import (
    FactID,
    JourneyID,
    ObligationID,
    OperationID,
    OracleID,
    PreparationID,
    PromiseID,
    RubricID,
    ScenarioID,
    StateKey,
    StateSchema,
    StateTag,
    parse_call_id,
    parse_case_key,
    parse_evidence_schema,
    parse_evidence_type,
    parse_identifier,
    parse_state_key,
    parse_state_schema,
)


_SCHEMAS = {
    "promise": "enchron.regression.promises",
    "fact": "enchron.regression.fact",
    "operation": "enchron.regression.operation",
    "oracle": "enchron.regression.oracle",
    "rubric": "enchron.regression.rubric",
    "preparation": "enchron.regression.preparation",
    "journey": "enchron.regression.journey",
    "scenario": "enchron.regression.scenario",
}
_CATALOG_SCHEMAS = frozenset(_SCHEMAS.values())
_HEADER_KEYS = frozenset(("schema", "schemaVersion"))
_IDENTIFIED_KEYS = _HEADER_KEYS | {"id"}
_CATALOG_DIRECTORIES = frozenset(
    (
        "promises",
        "facts",
        "operations",
        "oracles",
        "rubrics",
        "preparations",
        "journeys",
    )
)
_FEATURE = re.compile(r"[a-z0-9]+(?:-[a-z0-9]+)*")


def _error(code: str, location: str, detail: str) -> RegressionError:
    return RegressionError(code, location, detail)


def _thaw(value: Any) -> Any:
    if isinstance(value, Mapping):
        return {key: _thaw(item) for key, item in value.items()}
    if isinstance(value, tuple):
        return [_thaw(item) for item in value]
    return value


def _keys(
    payload: object,
    required: Iterable[str],
    optional: Iterable[str],
    location: str,
) -> Mapping[str, Any]:
    if not isinstance(payload, Mapping):
        raise _error("catalog.not_object", location, "expected a JSON object")
    required_set = frozenset(required)
    allowed = required_set | frozenset(optional)
    unknown = sorted(set(payload) - allowed)
    if unknown:
        raise _error(
            "catalog.unknown_key",
            location,
            "unknown key(s): " + ", ".join(unknown),
        )
    missing = sorted(required_set - set(payload))
    if missing:
        raise _error(
            "catalog.missing_key",
            location,
            "missing key(s): " + ", ".join(missing),
        )
    return payload


def _array(value: object, location: str) -> Tuple[Any, ...]:
    if not isinstance(value, tuple):
        raise _error("catalog.not_array", location, "expected a JSON array")
    return value


def _unique_values(
    value: object, location: str, code: str, label: str
) -> Tuple[Any, ...]:
    values = _array(value, location)
    try:
        duplicate = len(values) != len(set(values))
    except TypeError as error:
        raise _error("catalog.invalid_item", location, f"{label} items must be scalar") from error
    if duplicate:
        raise _error(code, location, f"{label} repeated")
    return values


def _enum(value: object, enum_type: Any, location: str) -> Any:
    if not isinstance(value, str):
        raise _error("catalog.invalid_enum", location, "enum value must be a string")
    try:
        return enum_type(value)
    except ValueError as error:
        raise _error("catalog.invalid_enum", location, f"unknown value {value!r}") from error


def _string(value: object, location: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise _error("catalog.invalid_string", location, "expected non-empty text")
    return value


def _feature(value: object, location: str) -> str:
    value = _string(value, location)
    if _FEATURE.fullmatch(value) is None:
        raise _error(
            "catalog.invalid_feature",
            location,
            "feature must be a stable lowercase slug",
        )
    return value


def _identifier(kind: str, value: object, location: str) -> Any:
    return parse_identifier(kind, value, location)


def _expected_kind(root: Path, path: Path) -> Optional[str]:
    parts = path.relative_to(root).parts
    if len(parts) == 2 and parts[0] == "promises":
        return "promise"
    if len(parts) == 2 and parts[0] == "facts":
        return "fact"
    if len(parts) == 2 and parts[0] == "operations":
        return "operation"
    if len(parts) == 2 and parts[0] == "oracles":
        return "oracle"
    if len(parts) == 2 and parts[0] == "rubrics":
        return "rubric"
    if len(parts) == 2 and parts[0] == "preparations":
        return "preparation"
    if len(parts) == 3 and parts[0] == "journeys" and parts[2] == "journey.md":
        return "journey"
    if len(parts) == 4 and parts[0] == "journeys" and parts[2] == "scenarios":
        return "scenario"
    if parts and parts[0] in _CATALOG_DIRECTORIES:
        raise _error(
            "catalog.invalid_path",
            str(path),
            "contract Markdown is outside the authoritative Catalog layout",
        )
    return None


def _document(root: Path, path: Path, expected_kind: str) -> FrontMatterDocument:
    document = load_frontmatter(path)
    metadata = _keys(
        document.metadata,
        _HEADER_KEYS,
        set(document.metadata) - _HEADER_KEYS,
        str(path),
    )
    expected_schema = _SCHEMAS[expected_kind]
    if metadata["schema"] != expected_schema:
        raise _error(
            "catalog.path_kind_mismatch",
            str(path),
            f"path requires schema {expected_schema!r}",
        )
    if type(metadata["schemaVersion"]) is not int or metadata["schemaVersion"] != 1:
        raise _error(
            "catalog.unsupported_schema_version",
            str(path),
            "schemaVersion must be integer 1",
        )
    return document


def _reject_misplaced_regression_document(path: Path) -> None:
    try:
        document = load_frontmatter(path)
    except RegressionError:
        return
    schema = document.metadata.get("schema")
    if schema in _CATALOG_SCHEMAS:
        raise _error(
            "catalog.invalid_path",
            str(path),
            "Regression contract Markdown is outside the authoritative Catalog layout",
        )


def _parse_promise_document(
    path: Path, document: FrontMatterDocument
) -> Tuple[str, Tuple[PromiseContract, ...]]:
    location = str(path)
    data = _keys(
        document.metadata,
        _HEADER_KEYS | {"feature", "title", "promises"},
        (),
        location,
    )
    feature = _feature(data["feature"], f"{location}.feature")
    _string(data["title"], f"{location}.title")
    if path.stem != feature:
        raise _error(
            "catalog.promise_path_mismatch",
            location,
            f"Promise feature {feature!r} must be stored in {feature}.md",
        )
    items = _array(data["promises"], f"{location}.promises")
    if not items:
        raise _error(
            "catalog.empty_promise_document",
            location,
            "a Promise feature document must contain a commitment",
        )
    promises = []
    for index, item in enumerate(items):
        item_location = f"{location}.promises[{index}]"
        promise = _keys(
            item,
            {"id", "title", "statement", "automation"},
            (),
            item_location,
        )
        automation = _keys(
            promise["automation"],
            {"scope"},
            {"reason"},
            f"{item_location}.automation",
        )
        promise_id = PromiseID(
            _identifier("promise", promise["id"], f"{item_location}.id")
        )
        if not str(promise_id).startswith(f"promise:{feature}:"):
            raise _error(
                "catalog.promise_feature_mismatch",
                f"{item_location}.id",
                f"Promise ID must belong to feature {feature!r}",
            )
        reason = automation.get("reason")
        promises.append(
            PromiseContract(
                promise_id,
                _string(promise["title"], f"{item_location}.title"),
                _string(promise["statement"], f"{item_location}.statement"),
                _enum(
                    automation["scope"],
                    AutomationScope,
                    f"{item_location}.automation.scope",
                ),
                None
                if reason is None
                else _string(reason, f"{item_location}.automation.reason"),
                document.body,
                document.source_digest,
            )
        )
    return feature, tuple(promises)


def _parse_fact(document: FrontMatterDocument, location: str) -> FactDeclaration:
    data = _keys(
        document.metadata,
        _IDENTIFIED_KEYS | {"title", "statement", "valueType", "value", "provenance"},
        (),
        location,
    )
    return FactDeclaration(
        FactID(_identifier("fact", data["id"], f"{location}.id")),
        _string(data["title"], f"{location}.title"),
        _string(data["statement"], f"{location}.statement"),
        _enum(data["valueType"], ArgumentValueKind, f"{location}.valueType"),
        document.body,
        document.source_digest,
    )


def _parse_implementation(value: object, location: str) -> Tuple[str, Any]:
    data = _keys(value, {"locator", "digest"}, (), location)
    return (
        _string(data["locator"], f"{location}.locator"),
        _identifier("digest", data["digest"], f"{location}.digest"),
    )


def _parse_argument_schema(value: object, location: str) -> ArgumentSchema:
    data = _keys(value, {"fields", "additionalProperties"}, {"rules"}, location)
    if data["additionalProperties"] is not False:
        raise _error(
            "catalog.argument_additional_properties",
            f"{location}.additionalProperties",
            "additionalProperties must be false",
        )
    fields = []
    for index, item in enumerate(_array(data["fields"], f"{location}.fields")):
        field_location = f"{location}.fields[{index}]"
        field_data = _keys(item, {"name", "type", "required"}, (), field_location)
        fields.append(
            ArgumentField(
                _string(field_data["name"], f"{field_location}.name"),
                _enum(
                    field_data["type"],
                    ArgumentValueKind,
                    f"{field_location}.type",
                ),
                field_data["required"],
            )
        )
    rules = []
    for index, item in enumerate(_array(data.get("rules", ()), f"{location}.rules")):
        rule_location = f"{location}.rules[{index}]"
        if not isinstance(item, Mapping):
            raise _error("catalog.invalid_argument_rule", rule_location, "expected an object")
        kind = _string(item.get("kind"), f"{rule_location}.kind")
        if kind in ("at-least-one", "all-or-none"):
            rule_data = _keys(item, {"kind", "fields"}, (), rule_location)
            rules.append(ArgumentRule(kind, fields=tuple(_array(rule_data["fields"], f"{rule_location}.fields"))))
        elif kind == "exactly-one-group":
            rule_data = _keys(item, {"kind", "groups"}, (), rule_location)
            rules.append(ArgumentRule(kind, groups=tuple(tuple(_array(group, f"{rule_location}.groups")) for group in _array(rule_data["groups"], f"{rule_location}.groups"))))
        elif kind == "when-equals":
            rule_data = _keys(item, {"kind", "discriminator", "cases"}, (), rule_location)
            cases = []
            for case_index, case in enumerate(_array(rule_data["cases"], f"{rule_location}.cases")):
                case_location = f"{rule_location}.cases[{case_index}]"
                case_data = _keys(case, {"value", "required", "forbidden"}, (), case_location)
                cases.append(ArgumentRuleCase(
                    _string(case_data["value"], f"{case_location}.value"),
                    tuple(_array(case_data["required"], f"{case_location}.required")),
                    tuple(_array(case_data["forbidden"], f"{case_location}.forbidden")),
                ))
            rules.append(ArgumentRule(kind, discriminator=_string(rule_data["discriminator"], f"{rule_location}.discriminator"), cases=tuple(cases)))
        else:
            raise _error("catalog.invalid_argument_rule", rule_location, f"unknown rule kind {kind}")
    return ArgumentSchema(tuple(fields), tuple(rules))


def _parse_evidence_schemas(
    value: object, location: str
) -> FrozenSet[EvidenceSchemaPair]:
    result = []
    for index, item in enumerate(_array(value, location)):
        item_location = f"{location}[{index}]"
        data = _keys(item, {"evidenceType", "evidenceSchema"}, (), item_location)
        result.append(
            EvidenceSchemaPair(
                parse_evidence_type(
                    data["evidenceType"], f"{item_location}.evidenceType"
                ),
                parse_evidence_schema(
                    data["evidenceSchema"], f"{item_location}.evidenceSchema"
                ),
            )
        )
    if len(result) != len(set(result)):
        raise _error(
            "catalog.duplicate_evidence_schema_pair",
            location,
            "an evidence type and schema pair may appear only once",
        )
    return frozenset(result)


def _parse_blockers(value: object, location: str) -> Tuple[ContractBlocker, ...]:
    result = []
    for index, item in enumerate(_array(value, location)):
        item_location = f"{location}[{index}]"
        if not isinstance(item, Mapping):
            raise _error(
                "catalog.expected_object", item_location, "expected an object"
            )
        kind = item.get("kind")
        if kind == "human-coverage":
            data = _keys(item, {"kind", "questionId", "detail"}, (), item_location)
            result.append(
                HumanCoverageBlocker(
                    _string(data["questionId"], f"{item_location}.questionId"),
                    _string(data["detail"], f"{item_location}.detail"),
                )
            )
        elif kind == "implementation-gap":
            data = _keys(item, {"kind", "capability", "detail"}, (), item_location)
            result.append(
                ImplementationGapBlocker(
                    _string(data["capability"], f"{item_location}.capability"),
                    _string(data["detail"], f"{item_location}.detail"),
                )
            )
        else:
            raise _error(
                "catalog.unknown_blocker_kind",
                f"{item_location}.kind",
                "blocker kind must be human-coverage or implementation-gap",
            )
    return tuple(result)


def _parse_operation(document: FrontMatterDocument, location: str) -> OperationContract:
    data = _keys(
        document.metadata,
        _IDENTIFIED_KEYS
        | {
            "title",
            "role",
            "lanes",
            "argumentSchema",
            "invalidatesTags",
            "evidenceSchemas",
            "implementation",
        },
        (),
        location,
    )
    lane_values = _unique_values(
        data["lanes"], f"{location}.lanes", "catalog.duplicate_lane", "lane"
    )
    invalidates = _unique_values(
        data["invalidatesTags"],
        f"{location}.invalidatesTags",
        "catalog.duplicate_state_tag",
        "state tag",
    )
    locator, implementation_digest = _parse_implementation(
        data["implementation"], f"{location}.implementation"
    )
    return OperationContract(
        OperationID(_identifier("operation", data["id"], f"{location}.id")),
        _string(data["title"], f"{location}.title"),
        _enum(data["role"], OperationRole, f"{location}.role"),
        frozenset(
            _enum(item, BoundLane, f"{location}.lanes[{index}]")
            for index, item in enumerate(lane_values)
        ),
        _parse_argument_schema(data["argumentSchema"], f"{location}.argumentSchema"),
        frozenset(
            StateTag(
                _identifier(
                    "state_tag", item, f"{location}.invalidatesTags[{index}]"
                )
            )
            for index, item in enumerate(invalidates)
        ),
        _parse_evidence_schemas(
            data["evidenceSchemas"], f"{location}.evidenceSchemas"
        ),
        locator,
        implementation_digest,
        document.body,
        document.source_digest,
    )


def _parse_oracle(document: FrontMatterDocument, location: str) -> OracleContract:
    data = _keys(
        document.metadata,
        _IDENTIFIED_KEYS | {"title", "kind", "evidenceSchemas", "implementation"},
        (),
        location,
    )
    locator, implementation_digest = _parse_implementation(
        data["implementation"], f"{location}.implementation"
    )
    return OracleContract(
        OracleID(_identifier("oracle", data["id"], f"{location}.id")),
        _string(data["title"], f"{location}.title"),
        _enum(data["kind"], OracleKind, f"{location}.kind"),
        _parse_evidence_schemas(
            data["evidenceSchemas"], f"{location}.evidenceSchemas"
        ),
        locator,
        implementation_digest,
        document.body,
        document.source_digest,
    )


def _parse_rubric(document: FrontMatterDocument, location: str) -> RubricContract:
    data = _keys(
        document.metadata,
        _IDENTIFIED_KEYS | {"title", "criteria", "negativeControls"},
        (),
        location,
    )
    criteria = _unique_values(
        data["criteria"],
        f"{location}.criteria",
        "catalog.duplicate_rubric_item",
        "criterion",
    )
    negative_controls = _unique_values(
        data["negativeControls"],
        f"{location}.negativeControls",
        "catalog.duplicate_rubric_item",
        "negative control",
    )
    return RubricContract(
        RubricID(_identifier("rubric", data["id"], f"{location}.id")),
        _string(data["title"], f"{location}.title"),
        tuple(
            _string(item, f"{location}.criteria[{index}]")
            for index, item in enumerate(criteria)
        ),
        tuple(
            _string(item, f"{location}.negativeControls[{index}]")
            for index, item in enumerate(negative_controls)
        ),
        document.body,
        document.source_digest,
    )


def _parse_state_requirements(
    value: object, location: str
) -> Tuple[StateRequirement, ...]:
    result = []
    for index, item in enumerate(_array(value, location)):
        item_location = f"{location}[{index}]"
        data = _keys(item, {"key", "schema"}, (), item_location)
        result.append(
            StateRequirement(
                parse_state_key(data["key"], f"{item_location}.key"),
                parse_state_schema(data["schema"], f"{item_location}.schema"),
            )
        )
    return tuple(result)


def _parse_state_declarations(
    value: object, location: str
) -> Tuple[StateDeclaration, ...]:
    result = []
    for index, item in enumerate(_array(value, location)):
        item_location = f"{location}[{index}]"
        data = _keys(
            item,
            {"key", "schema", "producedByCall", "dependsOnTags"},
            (),
            item_location,
        )
        tags = _unique_values(
            data["dependsOnTags"],
            f"{item_location}.dependsOnTags",
            "catalog.duplicate_state_tag",
            "state tag",
        )
        result.append(
            StateDeclaration(
                parse_state_key(data["key"], f"{item_location}.key"),
                parse_state_schema(data["schema"], f"{item_location}.schema"),
                None
                if data["producedByCall"] is None
                else parse_call_id(
                    data["producedByCall"], f"{item_location}.producedByCall"
                ),
                tuple(
                    StateTag(
                        _identifier(
                            "state_tag",
                            tag,
                            f"{item_location}.dependsOnTags[{tag_index}]",
                        )
                    )
                    for tag_index, tag in enumerate(tags)
                ),
            )
        )
    return tuple(result)


def _parse_calls(
    value: object,
    location: str,
    operations_by_id: Mapping[OperationID, OperationContract],
) -> Tuple[OperationCall, ...]:
    calls = []
    for index, item in enumerate(_array(value, location)):
        call_location = f"{location}[{index}]"
        data = _keys(
            item,
            {"callId", "operation", "arguments", "maxInvocations"},
            (),
            call_location,
        )
        operation_id = OperationID(
            _identifier("operation", data["operation"], f"{call_location}.operation")
        )
        operation = operations_by_id.get(operation_id)
        if operation is None:
            raise _error(
                "catalog.unknown_operation",
                f"{call_location}.operation",
                f"unknown Operation {operation_id}",
            )
        calls.append(
            OperationCall(
                parse_call_id(data["callId"], f"{call_location}.callId"),
                operation_id,
                operation.argument_schema.canonicalize(
                    _thaw(data["arguments"]), f"{call_location}.arguments"
                ),
                data["maxInvocations"],
            )
        )
    return tuple(calls)


def _parse_preparation(
    document: FrontMatterDocument,
    location: str,
    operations_by_id: Mapping[OperationID, OperationContract],
) -> PreparationContract:
    data = _keys(
        document.metadata,
        _IDENTIFIED_KEYS
        | {
            "title",
            "lane",
            "estimatedCostMillis",
            "readiness",
            "blockers",
            "prerequisites",
            "operations",
            "produces",
        },
        (),
        location,
    )
    return PreparationContract(
        PreparationID(_identifier("preparation", data["id"], f"{location}.id")),
        _string(data["title"], f"{location}.title"),
        _enum(data["lane"], BoundLane, f"{location}.lane"),
        data["estimatedCostMillis"],
        _enum(data["readiness"], ContractReadiness, f"{location}.readiness"),
        _parse_blockers(data["blockers"], f"{location}.blockers"),
        _parse_state_requirements(
            data["prerequisites"], f"{location}.prerequisites"
        ),
        _parse_calls(data["operations"], f"{location}.operations", operations_by_id),
        _parse_state_declarations(data["produces"], f"{location}.produces"),
        document.body,
        document.source_digest,
    )


def _parse_journey(
    path: Path, document: FrontMatterDocument, location: str
) -> JourneyContract:
    data = _keys(
        document.metadata,
        _IDENTIFIED_KEYS
        | {"title", "scenarioRefs", "ordering", "sharedState"},
        (),
        location,
    )
    journey_id = JourneyID(_identifier("journey", data["id"], f"{location}.id"))
    expected_directory = str(journey_id).removeprefix("journey:")
    if path.parent.name != expected_directory:
        raise _error(
            "catalog.path_id_mismatch",
            location,
            f"Journey {journey_id} must be stored below {expected_directory!r}",
        )
    ordering = []
    for index, item in enumerate(_array(data["ordering"], f"{location}.ordering")):
        edge_location = f"{location}.ordering[{index}]"
        edge = _keys(item, {"before", "after"}, (), edge_location)
        ordering.append(
            (
                ScenarioID(
                    _identifier("scenario", edge["before"], f"{edge_location}.before")
                ),
                ScenarioID(
                    _identifier("scenario", edge["after"], f"{edge_location}.after")
                ),
            )
        )
    return JourneyContract(
        journey_id,
        _string(data["title"], f"{location}.title"),
        tuple(
            ScenarioID(
                _identifier("scenario", item, f"{location}.scenarioRefs[{index}]")
            )
            for index, item in enumerate(
                _array(data["scenarioRefs"], f"{location}.scenarioRefs")
            )
        ),
        tuple(ordering),
        _parse_state_requirements(data["sharedState"], f"{location}.sharedState"),
        document.body,
        document.source_digest,
    )


def _parse_obligations(
    value: object, location: str
) -> Tuple[EvidenceObligation, ...]:
    result = []
    for index, item in enumerate(_array(value, location)):
        item_location = f"{location}[{index}]"
        data = _keys(
            item,
            {
                "id",
                "artifactClass",
                "evidenceType",
                "evidenceSchema",
                "caseKey",
                "producedByCall",
                "oracle",
                "rubric",
            },
            (),
            item_location,
        )
        if data["artifactClass"] != ArtifactClass.COVERAGE.value:
            raise _error(
                "catalog.invalid_artifact_class",
                f"{item_location}.artifactClass",
                "artifactClass must be 'coverage'",
            )
        result.append(
            EvidenceObligation(
                ObligationID(
                    _identifier("obligation", data["id"], f"{item_location}.id")
                ),
                ArtifactClass.COVERAGE,
                parse_evidence_type(
                    data["evidenceType"], f"{item_location}.evidenceType"
                ),
                parse_evidence_schema(
                    data["evidenceSchema"], f"{item_location}.evidenceSchema"
                ),
                parse_case_key(data["caseKey"], f"{item_location}.caseKey"),
                None
                if data["producedByCall"] is None
                else parse_call_id(
                    data["producedByCall"], f"{item_location}.producedByCall"
                ),
                OracleID(
                    _identifier("oracle", data["oracle"], f"{item_location}.oracle")
                ),
                RubricID(
                    _identifier("rubric", data["rubric"], f"{item_location}.rubric")
                ),
            )
        )
    return tuple(result)


def _parse_scenario(
    path: Path,
    document: FrontMatterDocument,
    location: str,
    operations_by_id: Mapping[OperationID, OperationContract],
) -> ScenarioContract:
    data = _keys(
        document.metadata,
        _IDENTIFIED_KEYS
        | {
            "title",
            "journey",
            "promiseRefs",
            "applicability",
            "lane",
            "estimatedCostMillis",
            "staticCases",
            "readiness",
            "blockers",
            "prerequisites",
            "operations",
            "obligations",
            "success",
        },
        {"mainGateFor"},
        location,
    )
    journey_id = JourneyID(
        _identifier("journey", data["journey"], f"{location}.journey")
    )
    journey_directory = path.parent.parent.name
    if str(journey_id) != f"journey:{journey_directory}":
        raise _error(
            "catalog.path_id_mismatch",
            location,
            f"Scenario path belongs to journey:{journey_directory}",
        )
    scenario_id = ScenarioID(
        _identifier("scenario", data["id"], f"{location}.id")
    )
    if not str(scenario_id).startswith(f"scenario:{journey_directory}:"):
        raise _error(
            "catalog.path_id_mismatch",
            location,
            f"Scenario ID must belong to journey {journey_directory!r}",
        )
    main_gate_values = _unique_values(
        data.get("mainGateFor", ()),
        f"{location}.mainGateFor",
        "catalog.duplicate_main_gate_lane",
        "main gate lane",
    )
    obligations = _parse_obligations(data["obligations"], f"{location}.obligations")
    success = parse_success_expression(_thaw(data["success"]), f"{location}.success")
    validate_expression_obligations(
        success, tuple(item.id for item in obligations), f"{location}.success"
    )
    return ScenarioContract(
        scenario_id,
        _string(data["title"], f"{location}.title"),
        journey_id,
        tuple(
            PromiseID(
                _identifier("promise", item, f"{location}.promiseRefs[{index}]")
            )
            for index, item in enumerate(
                _array(data["promiseRefs"], f"{location}.promiseRefs")
            )
        ),
        parse_applicability(_thaw(data["applicability"]), f"{location}.applicability"),
        _enum(data["lane"], LaneRequirement, f"{location}.lane"),
        data["estimatedCostMillis"],
        tuple(
            parse_case_key(item, f"{location}.staticCases[{index}]")
            for index, item in enumerate(
                _array(data["staticCases"], f"{location}.staticCases")
            )
        ),
        _enum(data["readiness"], ContractReadiness, f"{location}.readiness"),
        _parse_blockers(data["blockers"], f"{location}.blockers"),
        _parse_state_requirements(
            data["prerequisites"], f"{location}.prerequisites"
        ),
        _parse_calls(data["operations"], f"{location}.operations", operations_by_id),
        obligations,
        success,
        frozenset(
            _enum(item, BoundLane, f"{location}.mainGateFor[{index}]")
            for index, item in enumerate(main_gate_values)
        ),
        document.body,
        document.source_digest,
    )


def _duplicates(values: Sequence[Any]) -> bool:
    return len(values) != len(set(values))


def _require_unique_contract_ids(groups: Iterable[Sequence[Any]]) -> None:
    identifiers = []
    for group in groups:
        identifiers.extend(item.id for item in group)
    if _duplicates(identifiers):
        seen = set()
        duplicate = next(item for item in identifiers if item in seen or seen.add(item))
        raise _error(
            "catalog.duplicate_id",
            str(duplicate),
            "contract ID declared more than once",
        )


def _executable_lanes(lane: LaneRequirement) -> frozenset:
    if lane is LaneRequirement.SIMULATOR:
        return frozenset((BoundLane.SIMULATOR,))
    if lane is LaneRequirement.DEVICE:
        return frozenset((BoundLane.DEVICE,))
    return frozenset((BoundLane.SIMULATOR, BoundLane.DEVICE))


def _validate_cycle(
    successors: Mapping[Any, Sequence[Any]], code: str, location: str
) -> None:
    active = set()
    complete = set()

    def visit(item: Any) -> None:
        if item in complete:
            return
        if item in active:
            raise _error(code, location, f"dependency cycle contains {item}")
        active.add(item)
        for successor in successors[item]:
            visit(successor)
        active.remove(item)
        complete.add(item)

    for item in successors:
        visit(item)


def _validate_journey_cycle(journey: JourneyContract) -> None:
    successors: Dict[ScenarioID, list] = {
        item: [] for item in journey.scenario_refs
    }
    for before, after in journey.ordering:
        successors[before].append(after)
    _validate_cycle(successors, "catalog.journey_cycle", str(journey.id))


def _state_identity(
    requirement: StateRequirement,
) -> Tuple[StateKey, StateSchema]:
    return requirement.key, requirement.schema


def _declaration_identity(
    declaration: StateDeclaration,
) -> Tuple[StateKey, StateSchema]:
    return declaration.key, declaration.schema


def _validate_catalog(catalog: DraftCatalog) -> None:
    promises = {item.id: item for item in catalog.promises}
    facts = {item.id: item for item in catalog.facts}
    operations = {item.id: item for item in catalog.operations}
    oracles = {item.id: item for item in catalog.oracles}
    rubrics = {item.id: item for item in catalog.rubrics}
    journeys = {item.id: item for item in catalog.journeys}
    scenarios = {item.id: item for item in catalog.scenarios}

    obligation_ids = [
        item.id for scenario in catalog.scenarios for item in scenario.obligations
    ]
    if _duplicates(obligation_ids):
        raise _error(
            "catalog.duplicate_obligation",
            "$catalog",
            "obligation IDs must be globally unique",
        )

    calls = [
        call
        for preparation in catalog.preparations
        for call in preparation.operations
    ] + [call for scenario in catalog.scenarios for call in scenario.operations]
    call_ids = [call.call_id for call in calls]
    if _duplicates(call_ids):
        raise _error(
            "catalog.duplicate_call",
            "$catalog",
            "call IDs must be globally unique",
        )

    state_producers: Dict[Tuple[StateKey, StateSchema], list] = {}
    for preparation in catalog.preparations:
        call_by_id = {call.call_id: call for call in preparation.operations}
        for call in preparation.operations:
            operation = operations[call.operation]
            if preparation.lane not in operation.lanes:
                raise _error(
                    "catalog.operation_lane_mismatch",
                    str(preparation.id),
                    f"{call.operation} does not support {preparation.lane.value}",
                )
        for declaration in preparation.produces:
            if declaration.produced_by_call is not None:
                call = call_by_id.get(declaration.produced_by_call)
                if call is None:
                    raise _error(
                        "catalog.unknown_state_producer",
                        str(preparation.id),
                        f"unknown state producer {declaration.produced_by_call}",
                    )
                producer = operations[call.operation]
                if producer.role is not OperationRole.SETUP:
                    raise _error(
                        "catalog.non_setup_state_producer",
                        str(preparation.id),
                        f"{call.operation} has role {producer.role.value}",
                    )
            state_producers.setdefault(_declaration_identity(declaration), []).append(
                preparation.id
            )

    requirements = []
    for preparation in catalog.preparations:
        requirements.extend(
            (preparation.id, item) for item in preparation.prerequisites
        )
    for scenario in catalog.scenarios:
        if scenario.readiness is ContractReadiness.READY:
            requirements.extend((scenario.id, item) for item in scenario.prerequisites)
    for journey in catalog.journeys:
        if any(
            scenarios[item].readiness is ContractReadiness.READY
            for item in journey.scenario_refs
        ):
            requirements.extend((journey.id, item) for item in journey.shared_state)
    for owner, requirement in requirements:
        if _state_identity(requirement) not in state_producers:
            raise _error(
                "catalog.unknown_state_requirement",
                str(owner),
                f"no Preparation produces {requirement.key!r} as {requirement.schema!r}",
            )

    preparation_successors: Dict[PreparationID, list] = {
        item.id: [] for item in catalog.preparations
    }
    for preparation in catalog.preparations:
        for prerequisite in preparation.prerequisites:
            for producer_id in state_producers[_state_identity(prerequisite)]:
                preparation_successors[producer_id].append(preparation.id)
    _validate_cycle(
        preparation_successors,
        "catalog.preparation_cycle",
        "$catalog.preparations",
    )

    main_gate_by_lane: Dict[BoundLane, ScenarioID] = {}
    covered_promises = set()
    for scenario in catalog.scenarios:
        executable_lanes = _executable_lanes(scenario.lane)
        invalid_main_gate_lanes = scenario.main_gate_for - executable_lanes
        if invalid_main_gate_lanes:
            raise _error(
                "catalog.invalid_main_gate_lane",
                str(scenario.id),
                "mainGateFor includes a lane on which the Scenario cannot execute",
            )
        for lane in scenario.main_gate_for:
            existing = main_gate_by_lane.get(lane)
            if existing is not None:
                raise _error(
                    "catalog.duplicate_main_gate",
                    lane.value,
                    f"{existing} and {scenario.id} both claim the lane",
                )
            main_gate_by_lane[lane] = scenario.id

        journey = journeys.get(scenario.journey)
        if journey is None:
            raise _error(
                "catalog.unknown_journey",
                str(scenario.id),
                f"unknown Journey {scenario.journey}",
            )
        if scenario.id not in journey.scenario_refs:
            raise _error(
                "catalog.journey_missing_scenario",
                str(journey.id),
                f"Journey does not list {scenario.id}",
            )
        for promise_id in scenario.promise_refs:
            promise = promises.get(promise_id)
            if promise is None:
                raise _error(
                    "catalog.unknown_promise",
                    str(scenario.id),
                    f"unknown Promise {promise_id}",
                )
            if promise.scope is AutomationScope.EXCLUDED:
                raise _error(
                    "catalog.excluded_promise_referenced",
                    str(scenario.id),
                    f"Scenario references excluded Promise {promise_id}",
                )
            covered_promises.add(promise_id)
        unknown_facts = referenced_facts(scenario.applicability) - frozenset(facts)
        if unknown_facts:
            raise _error(
                "catalog.unknown_fact",
                str(scenario.id),
                "unknown applicability Fact(s): " + ", ".join(sorted(unknown_facts)),
            )
        call_by_id = {item.call_id: item for item in scenario.operations}
        for call in scenario.operations:
            operation = operations[call.operation]
            if not executable_lanes.issubset(operation.lanes):
                raise _error(
                    "catalog.operation_lane_mismatch",
                    str(scenario.id),
                    f"{call.operation} does not support {scenario.lane.value}",
                )
        for obligation in scenario.obligations:
            pair = EvidenceSchemaPair(
                obligation.evidence_type, obligation.evidence_schema
            )
            if obligation.produced_by_call is None:
                if scenario.readiness is ContractReadiness.READY:
                    raise _error(
                        "catalog.unknown_obligation_producer",
                        str(obligation.id),
                        "ready obligation has no producer call",
                    )
                call = None
            else:
                call = call_by_id.get(obligation.produced_by_call)
            if obligation.produced_by_call is not None and call is None:
                raise _error(
                    "catalog.unknown_obligation_producer",
                    str(obligation.id),
                    f"unknown producer call {obligation.produced_by_call}",
                )
            if call is not None:
                producer = operations[call.operation]
                if producer.role in {
                    OperationRole.SETUP,
                    OperationRole.DIAGNOSTIC_BYPASS,
                }:
                    raise _error(
                        "catalog.non_evidence_coverage_producer",
                        str(obligation.id),
                        f"{producer.role.value} operations cannot earn coverage",
                    )
                if pair not in producer.evidence_schemas:
                    raise _error(
                        "catalog.unsupported_producer_evidence_schema",
                        str(obligation.id),
                        f"{call.operation} does not produce {pair.evidence_type} as {pair.evidence_schema}",
                    )
            oracle = oracles.get(obligation.oracle)
            if oracle is None:
                raise _error(
                    "catalog.unknown_oracle",
                    str(obligation.id),
                    f"unknown Oracle {obligation.oracle}",
                )
            if pair not in oracle.evidence_schemas:
                raise _error(
                    "catalog.unsupported_oracle_evidence_schema",
                    str(obligation.id),
                    f"{obligation.oracle} does not accept {pair.evidence_type} as {pair.evidence_schema}",
                )
            rubric = rubrics.get(obligation.rubric)
            if rubric is None:
                raise _error(
                    "catalog.unknown_rubric",
                    str(obligation.id),
                    f"unknown Rubric {obligation.rubric}",
                )
            if oracle.kind is OracleKind.AGENT and (
                not rubric.criteria or not rubric.negative_controls
            ):
                raise _error(
                    "catalog.agent_oracle_without_rubric_controls",
                    str(obligation.id),
                    "an Agent Oracle requires criteria and negative controls",
                )

    for promise in catalog.promises:
        if promise.scope is AutomationScope.INCLUDED and promise.id not in covered_promises:
            raise _error(
                "catalog.uncovered_included_promise",
                str(promise.id),
                "an included Promise must be covered by a Scenario",
            )

    claimed_scenarios = set()
    for journey in catalog.journeys:
        members = set(journey.scenario_refs)
        missing = members - set(scenarios)
        if missing:
            raise _error(
                "catalog.journey_missing_scenario",
                str(journey.id),
                "unknown Scenario(s): " + ", ".join(sorted(missing)),
            )
        for scenario_id in members:
            if scenarios[scenario_id].journey != journey.id:
                raise _error(
                    "catalog.scenario_journey_mismatch",
                    str(scenario_id),
                    f"Scenario declares {scenarios[scenario_id].journey}",
                )
        claimed_scenarios.update(members)
        for before, after in journey.ordering:
            if before not in members or after not in members:
                raise _error(
                    "catalog.external_ordering_reference",
                    str(journey.id),
                    "ordering edges must stay within the Journey",
                )
        _validate_journey_cycle(journey)
    unclaimed = set(scenarios) - claimed_scenarios
    if unclaimed:
        raise _error(
            "catalog.unclaimed_scenario",
            "$catalog",
            "Scenario(s) absent from Journey grouping: " + ", ".join(sorted(unclaimed)),
        )


def load_catalog(root: Path) -> DraftCatalog:
    root = Path(root)
    if not root.is_dir():
        raise _error(
            "catalog.root_not_directory",
            str(root),
            "Catalog root must be a directory",
        )

    documents = []
    for path in sorted(
        root.rglob("*.md"), key=lambda item: item.relative_to(root).as_posix()
    ):
        kind = _expected_kind(root, path)
        if kind is None:
            _reject_misplaced_regression_document(path)
            continue
        documents.append((kind, path, _document(root, path, kind)))

    promise_documents = [item for item in documents if item[0] == "promise"]
    if not promise_documents:
        raise _error(
            "catalog.empty_promise_features",
            str(root / "promises"),
            "Catalog v1 requires at least one Promise feature document",
        )

    promises = []
    promise_features = []
    facts = []
    operations = []
    oracles = []
    rubrics = []
    preparation_documents = []
    journeys = []
    scenario_documents = []
    for kind, path, document in documents:
        location = str(path)
        if kind == "promise":
            feature, feature_promises = _parse_promise_document(path, document)
            promise_features.append(feature)
            promises.extend(feature_promises)
        elif kind == "fact":
            facts.append(_parse_fact(document, location))
        elif kind == "operation":
            operations.append(_parse_operation(document, location))
        elif kind == "oracle":
            oracles.append(_parse_oracle(document, location))
        elif kind == "rubric":
            rubrics.append(_parse_rubric(document, location))
        elif kind == "preparation":
            preparation_documents.append((path, document))
        elif kind == "journey":
            journeys.append(_parse_journey(path, document, location))
        else:
            scenario_documents.append((path, document))

    if _duplicates(promise_features):
        raise _error(
            "catalog.duplicate_promise_feature",
            str(root / "promises"),
            "a Promise feature may be declared only once",
        )

    _require_unique_contract_ids((promises, facts, operations, oracles, rubrics, journeys))
    operations_by_id = {item.id: item for item in operations}
    preparations = [
        _parse_preparation(document, str(path), operations_by_id)
        for path, document in preparation_documents
    ]
    scenarios = [
        _parse_scenario(path, document, str(path), operations_by_id)
        for path, document in scenario_documents
    ]
    _require_unique_contract_ids(
        (
            promises,
            facts,
            operations,
            oracles,
            rubrics,
            preparations,
            journeys,
            scenarios,
        )
    )
    catalog = DraftCatalog(
        tuple(promises),
        tuple(facts),
        tuple(operations),
        tuple(oracles),
        tuple(rubrics),
        tuple(preparations),
        tuple(journeys),
        tuple(scenarios),
    )
    _validate_catalog(catalog)
    return catalog


__all__ = ("load_catalog",)
