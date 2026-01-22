# Relationship Patterns

Patterns for defining relationships between SQLModel tables.

## Overview

| Relationship | Example | Key Pattern |
|--------------|---------|-------------|
| One-to-Many | Team → Heroes | `list["Hero"]` + `back_populates` |
| One-to-One | User → Profile | `uselist=False` |
| Many-to-Many | Hero ↔ Powers | Link table with composite PK |
| Self-Referential | Category → Parent | `parent_id` references same table |
| Association Object | Student ↔ Course | Link table with extra fields |

## One-to-Many Relationship

**Use when:** One record relates to multiple records (e.g., Team has many Heroes).

```python
from sqlmodel import Field, Relationship, SQLModel

class Team(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)
    name: str

    # One team has many heroes
    heroes: list["Hero"] = Relationship(back_populates="team")

class Hero(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)
    name: str

    # Foreign key (required)
    team_id: int | None = Field(default=None, foreign_key="team.id")

    # Relationship back to team
    team: Team | None = Relationship(back_populates="heroes")
```

**Key points:**
- Parent has `list["Child"]` with `back_populates`
- Child has foreign key field + single relationship
- `back_populates` values must match field names exactly

### Creating Related Records

```python
# Method 1: Create parent first, then children
team = Team(name="Avengers")
session.add(team)
session.commit()

hero = Hero(name="Iron Man", team_id=team.id)
session.add(hero)
session.commit()

# Method 2: Create together via relationship
team = Team(name="Avengers", heroes=[
    Hero(name="Iron Man"),
    Hero(name="Thor")
])
session.add(team)
session.commit()
```

### Querying Related Records

```python
from sqlmodel import select

# Get team with heroes (eager loading)
from sqlalchemy.orm import selectinload

statement = select(Team).options(selectinload(Team.heroes)).where(Team.id == 1)
team = session.exec(statement).first()

# Get heroes for a team
heroes = team.heroes  # Lazy loads if not eager loaded

# Get team for a hero
hero = session.get(Hero, 1)
team = hero.team
```

## One-to-One Relationship

**Use when:** One record relates to exactly one other record (e.g., User has one Profile).

```python
class User(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)
    email: str = Field(unique=True)

    # One user has one profile
    profile: "Profile | None" = Relationship(
        back_populates="user",
        sa_relationship_kwargs={"uselist": False}
    )

class Profile(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)
    bio: str | None = None

    # Foreign key with unique constraint
    user_id: int = Field(foreign_key="user.id", unique=True)

    # Relationship back to user
    user: User = Relationship(back_populates="profile")
```

**Key points:**
- Use `uselist=False` on the parent side
- Foreign key should have `unique=True` to enforce 1:1
- Child side returns single object, not list

### Creating One-to-One Records

```python
# Create user with profile
user = User(
    email="john@example.com",
    profile=Profile(bio="Developer")
)
session.add(user)
session.commit()

# Or create separately
user = User(email="jane@example.com")
session.add(user)
session.commit()

profile = Profile(bio="Designer", user_id=user.id)
session.add(profile)
session.commit()
```

## Many-to-Many Relationship

**Use when:** Multiple records relate to multiple records (e.g., Heroes have many Powers, Powers belong to many Heroes).

```python
# Link table (no extra fields)
class HeroPowerLink(SQLModel, table=True):
    hero_id: int = Field(foreign_key="hero.id", primary_key=True)
    power_id: int = Field(foreign_key="power.id", primary_key=True)

class Hero(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)
    name: str

    powers: list["Power"] = Relationship(
        back_populates="heroes",
        link_model=HeroPowerLink
    )

class Power(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)
    name: str

    heroes: list["Hero"] = Relationship(
        back_populates="powers",
        link_model=HeroPowerLink
    )
```

**Key points:**
- Link table has composite primary key (both foreign keys)
- Both sides use `link_model` parameter
- Both sides have `list[...]` type

### Creating Many-to-Many Records

```python
# Create entities first
hero = Hero(name="Superman")
power1 = Power(name="Flight")
power2 = Power(name="Super Strength")

session.add_all([hero, power1, power2])
session.commit()

# Add via relationship
hero.powers.append(power1)
hero.powers.append(power2)
session.commit()

# Or create link directly
link = HeroPowerLink(hero_id=hero.id, power_id=power1.id)
session.add(link)
session.commit()
```

### Querying Many-to-Many

```python
# Get hero's powers
hero = session.get(Hero, 1)
for power in hero.powers:
    print(power.name)

# Get heroes with specific power
statement = select(Hero).join(HeroPowerLink).where(HeroPowerLink.power_id == 1)
heroes = session.exec(statement).all()

# Eager load
from sqlalchemy.orm import selectinload
statement = select(Hero).options(selectinload(Hero.powers))
heroes = session.exec(statement).all()
```

## Self-Referential Relationship

**Use when:** Records relate to other records of the same type (e.g., Categories with parent/children).

```python
class Category(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)
    name: str

    # Foreign key to same table
    parent_id: int | None = Field(default=None, foreign_key="category.id")

    # Parent relationship
    parent: "Category | None" = Relationship(
        back_populates="children",
        sa_relationship_kwargs={"remote_side": "Category.id"}
    )

    # Children relationship
    children: list["Category"] = Relationship(back_populates="parent")
```

**Key points:**
- Foreign key references same table
- `remote_side` specifies which side is the "parent"
- Parent is singular, children is list

### Working with Self-Referential

```python
# Create hierarchy
root = Category(name="Electronics")
session.add(root)
session.commit()

phones = Category(name="Phones", parent_id=root.id)
laptops = Category(name="Laptops", parent_id=root.id)
session.add_all([phones, laptops])
session.commit()

iphone = Category(name="iPhone", parent_id=phones.id)
session.add(iphone)
session.commit()

# Navigate hierarchy
category = session.get(Category, iphone.id)
print(category.parent.name)  # "Phones"
print(category.parent.parent.name)  # "Electronics"

# Get all children
electronics = session.get(Category, root.id)
for child in electronics.children:
    print(child.name)  # "Phones", "Laptops"
```

### Recursive Query (All Descendants)

```python
from sqlalchemy import text

# PostgreSQL recursive CTE
def get_all_descendants(session: Session, category_id: int) -> list[Category]:
    query = text("""
        WITH RECURSIVE descendants AS (
            SELECT id, name, parent_id
            FROM category
            WHERE parent_id = :category_id

            UNION ALL

            SELECT c.id, c.name, c.parent_id
            FROM category c
            INNER JOIN descendants d ON c.parent_id = d.id
        )
        SELECT id FROM descendants
    """)

    result = session.exec(query, {"category_id": category_id})
    ids = [row[0] for row in result]
    return session.exec(select(Category).where(Category.id.in_(ids))).all()
```

## Association Object Pattern

**Use when:** Many-to-many with extra data on the relationship (e.g., Student-Course with enrollment date and grade).

```python
from datetime import datetime, timezone

class Enrollment(SQLModel, table=True):
    """Association object with extra fields"""
    student_id: int = Field(foreign_key="student.id", primary_key=True)
    course_id: int = Field(foreign_key="course.id", primary_key=True)

    # Extra fields on the relationship
    enrolled_at: datetime = Field(
        default_factory=lambda: datetime.now(timezone.utc)
    )
    grade: float | None = Field(default=None)

    # Relationships to both sides
    student: "Student" = Relationship(back_populates="enrollments")
    course: "Course" = Relationship(back_populates="enrollments")

class Student(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)
    name: str

    # Relationship to association object
    enrollments: list[Enrollment] = Relationship(back_populates="student")

class Course(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)
    title: str

    # Relationship to association object
    enrollments: list[Enrollment] = Relationship(back_populates="course")
```

### Working with Association Objects

```python
# Create entities
student = Student(name="Alice")
course = Course(title="Database Design")
session.add_all([student, course])
session.commit()

# Create enrollment with extra data
enrollment = Enrollment(
    student_id=student.id,
    course_id=course.id,
    grade=95.5
)
session.add(enrollment)
session.commit()

# Access via relationships
for enrollment in student.enrollments:
    print(f"{enrollment.course.title}: {enrollment.grade}")

# Query with grade filter
statement = (
    select(Student)
    .join(Enrollment)
    .where(Enrollment.grade >= 90)
)
honor_students = session.exec(statement).all()
```

## Cascade Delete

**Configure automatic deletion of related records.**

```python
class Team(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)
    name: str

    # Cascade delete heroes when team is deleted
    heroes: list["Hero"] = Relationship(
        back_populates="team",
        sa_relationship_kwargs={"cascade": "all, delete-orphan"}
    )

class Hero(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)
    name: str
    team_id: int | None = Field(default=None, foreign_key="team.id")
    team: Team | None = Relationship(back_populates="heroes")
```

**Cascade options:**
- `save-update`: Cascade saves (default)
- `delete`: Cascade deletes
- `delete-orphan`: Delete when removed from parent
- `all`: All of the above
- `all, delete-orphan`: Full cascade

## Lazy Loading Options

```python
class Team(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)
    name: str

    # Lazy loading options
    heroes: list["Hero"] = Relationship(
        back_populates="team",
        sa_relationship_kwargs={
            "lazy": "selectin"  # Options: select, joined, subquery, selectin, raise
        }
    )
```

**Loading strategies:**
- `select`: Load on first access (default, causes N+1)
- `joined`: JOIN in same query
- `subquery`: Separate subquery
- `selectin`: IN query (best for collections)
- `raise`: Raise error if accessed (prevents N+1)

## Complete Example: Blog System

```python
from datetime import datetime, timezone
from sqlmodel import Field, Relationship, SQLModel

# Association table for tags
class PostTagLink(SQLModel, table=True):
    post_id: int = Field(foreign_key="post.id", primary_key=True)
    tag_id: int = Field(foreign_key="tag.id", primary_key=True)

class User(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)
    username: str = Field(unique=True)

    # One-to-Many: User has many posts
    posts: list["Post"] = Relationship(
        back_populates="author",
        sa_relationship_kwargs={"cascade": "all, delete-orphan"}
    )

    # One-to-Many: User has many comments
    comments: list["Comment"] = Relationship(back_populates="author")

class Post(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)
    title: str
    content: str
    created_at: datetime = Field(
        default_factory=lambda: datetime.now(timezone.utc)
    )

    # Many-to-One: Post belongs to user
    author_id: int = Field(foreign_key="user.id")
    author: User = Relationship(back_populates="posts")

    # One-to-Many: Post has many comments
    comments: list["Comment"] = Relationship(
        back_populates="post",
        sa_relationship_kwargs={"cascade": "all, delete-orphan"}
    )

    # Many-to-Many: Post has many tags
    tags: list["Tag"] = Relationship(
        back_populates="posts",
        link_model=PostTagLink
    )

class Comment(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)
    content: str
    created_at: datetime = Field(
        default_factory=lambda: datetime.now(timezone.utc)
    )

    # Many-to-One: Comment belongs to post
    post_id: int = Field(foreign_key="post.id")
    post: "Post" = Relationship(back_populates="comments")

    # Many-to-One: Comment belongs to user
    author_id: int = Field(foreign_key="user.id")
    author: User = Relationship(back_populates="comments")

    # Self-referential: Reply to another comment
    parent_id: int | None = Field(default=None, foreign_key="comment.id")
    parent: "Comment | None" = Relationship(
        back_populates="replies",
        sa_relationship_kwargs={"remote_side": "Comment.id"}
    )
    replies: list["Comment"] = Relationship(back_populates="parent")

class Tag(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)
    name: str = Field(unique=True)

    # Many-to-Many: Tag has many posts
    posts: list[Post] = Relationship(
        back_populates="tags",
        link_model=PostTagLink
    )
```
