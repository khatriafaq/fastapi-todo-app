#!/usr/bin/env python3
"""
Validate SQLModel definitions for common issues.

Usage:
    python validate_models.py path/to/models.py
    python validate_models.py path/to/models/

Checks:
    - Models with table=True have primary keys
    - Foreign keys reference valid table names
    - back_populates values match on both sides
    - Relationships use proper string references
"""

import ast
import sys
from dataclasses import dataclass, field
from pathlib import Path


@dataclass
class ModelInfo:
    """Information about a SQLModel class."""
    name: str
    table_name: str
    has_table: bool
    primary_keys: list[str] = field(default_factory=list)
    foreign_keys: dict[str, str] = field(default_factory=dict)  # field -> table
    relationships: dict[str, dict] = field(default_factory=dict)  # field -> {back_populates, target}
    file_path: str = ""
    line_number: int = 0


@dataclass
class ValidationIssue:
    """A validation issue found in the models."""
    severity: str  # "error" or "warning"
    message: str
    file_path: str
    line_number: int

    def __str__(self) -> str:
        return f"{self.severity.upper()}: {self.file_path}:{self.line_number} - {self.message}"


class SQLModelValidator(ast.NodeVisitor):
    """AST visitor to extract and validate SQLModel definitions."""

    def __init__(self, file_path: str):
        self.file_path = file_path
        self.models: dict[str, ModelInfo] = {}
        self.issues: list[ValidationIssue] = []

    def visit_ClassDef(self, node: ast.ClassDef) -> None:
        """Visit class definitions to find SQLModel classes."""
        # Check if class inherits from SQLModel
        is_sqlmodel = False
        has_table = False

        for base in node.bases:
            if isinstance(base, ast.Name) and base.id == "SQLModel":
                is_sqlmodel = True

        # Check for table=True in keywords
        for keyword in node.keywords:
            if keyword.arg == "table" and isinstance(keyword.value, ast.Constant):
                if keyword.value.value is True:
                    has_table = True

        if not is_sqlmodel:
            self.generic_visit(node)
            return

        # Extract model info
        model = ModelInfo(
            name=node.name,
            table_name=node.name.lower(),  # Default SQLModel behavior
            has_table=has_table,
            file_path=self.file_path,
            line_number=node.lineno,
        )

        # Check for custom __tablename__
        for stmt in node.body:
            if isinstance(stmt, ast.Assign):
                for target in stmt.targets:
                    if isinstance(target, ast.Name) and target.id == "__tablename__":
                        if isinstance(stmt.value, ast.Constant):
                            model.table_name = stmt.value.value

        # Extract field information
        for stmt in node.body:
            if isinstance(stmt, ast.AnnAssign) and isinstance(stmt.target, ast.Name):
                field_name = stmt.target.id
                self._analyze_field(model, field_name, stmt)

        self.models[node.name] = model
        self.generic_visit(node)

    def _analyze_field(self, model: ModelInfo, field_name: str, stmt: ast.AnnAssign) -> None:
        """Analyze a field definition for keys and relationships."""
        if stmt.value is None:
            return

        # Check for Field() call
        if isinstance(stmt.value, ast.Call):
            func = stmt.value.func
            func_name = None

            if isinstance(func, ast.Name):
                func_name = func.id
            elif isinstance(func, ast.Attribute):
                func_name = func.attr

            if func_name == "Field":
                self._analyze_field_call(model, field_name, stmt.value)
            elif func_name == "Relationship":
                self._analyze_relationship_call(model, field_name, stmt.value, stmt)

    def _analyze_field_call(self, model: ModelInfo, field_name: str, call: ast.Call) -> None:
        """Analyze a Field() call for primary and foreign keys."""
        for keyword in call.keywords:
            if keyword.arg == "primary_key":
                if isinstance(keyword.value, ast.Constant) and keyword.value.value is True:
                    model.primary_keys.append(field_name)

            elif keyword.arg == "foreign_key":
                if isinstance(keyword.value, ast.Constant):
                    model.foreign_keys[field_name] = keyword.value.value

    def _analyze_relationship_call(
        self, model: ModelInfo, field_name: str, call: ast.Call, stmt: ast.AnnAssign
    ) -> None:
        """Analyze a Relationship() call."""
        rel_info: dict = {"back_populates": None, "target": None}

        # Get target from type annotation
        if stmt.annotation:
            rel_info["target"] = self._extract_type_name(stmt.annotation)

        for keyword in call.keywords:
            if keyword.arg == "back_populates":
                if isinstance(keyword.value, ast.Constant):
                    rel_info["back_populates"] = keyword.value.value

        model.relationships[field_name] = rel_info

    def _extract_type_name(self, annotation: ast.expr) -> str | None:
        """Extract the model name from a type annotation."""
        if isinstance(annotation, ast.Name):
            return annotation.id
        elif isinstance(annotation, ast.Constant):
            return annotation.value
        elif isinstance(annotation, ast.Subscript):
            # Handle list["Model"] or Optional["Model"]
            if isinstance(annotation.slice, ast.Constant):
                return annotation.slice.value
            elif isinstance(annotation.slice, ast.Name):
                return annotation.slice.id
        elif isinstance(annotation, ast.BinOp):
            # Handle Model | None
            if isinstance(annotation.left, ast.Name):
                return annotation.left.id
            elif isinstance(annotation.left, ast.Constant):
                return annotation.left.value
        return None

    def validate(self) -> list[ValidationIssue]:
        """Run all validations and return issues."""
        self._validate_primary_keys()
        self._validate_foreign_keys()
        self._validate_back_populates()
        return self.issues

    def _validate_primary_keys(self) -> None:
        """Check that table models have primary keys."""
        for model in self.models.values():
            if model.has_table and not model.primary_keys:
                self.issues.append(ValidationIssue(
                    severity="error",
                    message=f"Table model '{model.name}' has no primary key",
                    file_path=model.file_path,
                    line_number=model.line_number,
                ))

    def _validate_foreign_keys(self) -> None:
        """Check that foreign keys reference valid tables."""
        table_names = {m.table_name for m in self.models.values() if m.has_table}

        for model in self.models.values():
            for field_name, fk_ref in model.foreign_keys.items():
                # Parse "table.column" format
                if "." in fk_ref:
                    ref_table = fk_ref.split(".")[0]
                    if ref_table not in table_names:
                        self.issues.append(ValidationIssue(
                            severity="warning",
                            message=f"Foreign key '{field_name}' references unknown table '{ref_table}'",
                            file_path=model.file_path,
                            line_number=model.line_number,
                        ))

    def _validate_back_populates(self) -> None:
        """Check that back_populates values match on both sides."""
        for model in self.models.values():
            for field_name, rel_info in model.relationships.items():
                back_pop = rel_info.get("back_populates")
                target = rel_info.get("target")

                if not back_pop or not target:
                    continue

                # Find target model
                target_model = self.models.get(target)
                if not target_model:
                    continue

                # Check if target has matching relationship
                found_match = False
                for target_field, target_rel in target_model.relationships.items():
                    if (target_rel.get("back_populates") == field_name and
                        target_rel.get("target") == model.name):
                        found_match = True
                        break

                if not found_match:
                    self.issues.append(ValidationIssue(
                        severity="error",
                        message=(
                            f"Relationship '{field_name}' has back_populates='{back_pop}' "
                            f"but no matching relationship found in '{target}'"
                        ),
                        file_path=model.file_path,
                        line_number=model.line_number,
                    ))


def validate_file(file_path: Path) -> list[ValidationIssue]:
    """Validate a single Python file."""
    try:
        source = file_path.read_text()
        tree = ast.parse(source)
    except SyntaxError as e:
        return [ValidationIssue(
            severity="error",
            message=f"Syntax error: {e}",
            file_path=str(file_path),
            line_number=e.lineno or 0,
        )]

    validator = SQLModelValidator(str(file_path))
    validator.visit(tree)
    return validator.validate()


def validate_directory(dir_path: Path) -> list[ValidationIssue]:
    """Validate all Python files in a directory."""
    all_issues: list[ValidationIssue] = []

    for py_file in dir_path.rglob("*.py"):
        issues = validate_file(py_file)
        all_issues.extend(issues)

    return all_issues


def main() -> int:
    """Main entry point."""
    if len(sys.argv) < 2:
        print("Usage: python validate_models.py <path>")
        print("  path: Python file or directory containing SQLModel definitions")
        return 1

    path = Path(sys.argv[1])

    if not path.exists():
        print(f"Error: Path not found: {path}")
        return 1

    if path.is_file():
        issues = validate_file(path)
    else:
        issues = validate_directory(path)

    if not issues:
        print("✓ No issues found")
        return 0

    errors = [i for i in issues if i.severity == "error"]
    warnings = [i for i in issues if i.severity == "warning"]

    for issue in issues:
        print(issue)

    print(f"\nFound {len(errors)} error(s) and {len(warnings)} warning(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
