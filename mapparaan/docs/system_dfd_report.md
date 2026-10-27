# System Data Flow Diagrams (DFDs)

This document contains the Data Flow Diagrams (DFDs) for the Mapparaan project. The diagrams are created using the Gane and Sarson model, based on the actual implementation in the repository. Each level of the DFD is explained in detail.

---

## Level 0: Context Diagram

The Level 0 Context Diagram represents the entire Mapparaan system as a single process, showing its interactions with external entities.

```mermaid
graph TD
    %% External Entities
    User([User]):::external
    Nominatim([Nominatim API]):::external
    OSRM([OSRM API]):::external
    OpenStreetMap([OpenStreetMap]):::external
    Supabase([Supabase Database]):::external

    %% Process
    P0([Mapparaan System]):::process

    %% Data Flows
    User -->|Searches Places, Plans Routes, Saves Places, Views History, Uploads Memory Pins| P0
    P0 -->|Displays Routes, Fares, ETAs, Saved Places, Trip History| User
    P0 -->|Requests Place Data| Nominatim
    Nominatim -->|Returns Place Data| P0
    P0 -->|Requests Route Data| OSRM
    OSRM -->|Returns Route Data| P0
    P0 -->|Requests Map Tiles| OpenStreetMap
    OpenStreetMap -->|Returns Map Tiles| P0
    P0 -->|Stores and Retrieves Data| Supabase

    classDef external fill:#f9f,stroke:#333,stroke-width:2px;
    classDef process fill:#bbf,stroke:#333,stroke-width:2px;

Level 1: System DFD
The Level 1 DFD breaks down the Mapparaan system into its major processes, data stores, and data flows.

    graph TD
    %% External Entities
    User([User]):::external
    Nominatim([Nominatim API]):::external
    OSRM([OSRM API]):::external
    OpenStreetMap([OpenStreetMap]):::external

    %% Processes
    P1([Place Search]):::process
    P2([Route Planning]):::process
    P3([Saved Places Management]):::process
    P4([Trip History Management]):::process
    P5([Memory Pin Management]):::process
    P6([User Preferences Management]):::process

    %% Data Stores
    Supabase[Supabase Database]:::datastore

    %% Data Flows
    User -->|Searches Places| P1
    User -->|Plans Routes| P2
    User -->|Saves Places| P3
    User -->|Views Trip History| P4
    User -->|Uploads Memory Pins| P5
    User -->|Updates Preferences| P6

    P1 -->|Requests Place Data| Nominatim
    Nominatim -->|Returns Place Data| P1

    P2 -->|Requests Route Data| OSRM
    OSRM -->|Returns Route Data| P2

    P2 -->|Requests Map Tiles| OpenStreetMap
    OpenStreetMap -->|Returns Map Tiles| P2

    P3 -->|Stores and Retrieves Saved Places| Supabase
    P4 -->|Stores and Retrieves Trip History| Supabase
    P5 -->|Stores and Retrieves Memory Pins| Supabase
    P6 -->|Stores and Retrieves Preferences| Supabase

    classDef external fill:#f9f,stroke:#333,stroke-width:2px;
    classDef process fill:#bbf,stroke:#333,stroke-width:2px;
    classDef datastore fill:#ff9,stroke:#333,stroke-width:2px;

Explanation:
Processes:

Place Search: Handles user place search requests via Nominatim.
Route Planning: Plans routes using OSRM and GTFS data.
Saved Places Management: Manages user-saved places in Supabase.
Trip History Management: Manages user trip history in Supabase.
Memory Pin Management: Manages user-uploaded memory pins in Supabase.
User Preferences Management: Manages user preferences in Supabase.

Data Stores:

Supabase Database: Stores user data, preferences, saved places, trip history, and memory pins.


Level 2: Route Planning
This diagram provides a detailed view of the Route Planning process.

graph TD
    %% External Entities
    User([User]):::external
    OSRM([OSRM API]):::external

    %% Process
    P2([Route Planning]):::process

    %% Data Stores
    GTFS[GTFS Data]:::datastore
    FareConfig[Fare Configuration]:::datastore

    %% Data Flows
    User -->|Plans Routes| P2
    P2 -->|Requests Walking/Driving Routes| OSRM
    OSRM -->|Returns Walking/Driving Routes| P2
    P2 -->|Processes Transit Routes| GTFS
    P2 -->|Calculates Fares and ETAs| FareConfig
    P2 -->|Displays Routes, Fares, and ETAs| User

    classDef external fill:#f9f,stroke:#333,stroke-width:2px;
    classDef process fill:#bbf,stroke:#333,stroke-width:2px;
    classDef datastore fill:#ff9,stroke:#333,stroke-width:2px;

    Level 2: Saved Places Management

    graph TD
    %% External Entities
    User([User]):::external

    %% Process
    P3([Saved Places Management]):::process

    %% Data Stores
    Supabase[Supabase Database]:::datastore

    %% Data Flows
    User -->|Saves Places| P3
    User -->|Retrieves Saved Places| P3
    P3 -->|Stores Saved Places| Supabase
    P3 -->|Retrieves Saved Places| Supabase
    P3 -->|Displays Saved Places| User

    classDef external fill:#f9f,stroke:#333,stroke-width:2px;
    classDef process fill:#bbf,stroke:#333,stroke-width:2px;
    classDef datastore fill:#ff9,stroke:#333,stroke-width:2px;

    Level 2: Memory Pin Management

    graph TD
    %% External Entities
    User([User]):::external

    %% Process
    P5([Memory Pin Management]):::process

    %% Data Stores
    Supabase[Supabase Database]:::datastore

    %% Data Flows
    User -->|Uploads Memory Pins| P5
    P5 -->|Stores Memory Pins| Supabase
    P5 -->|Retrieves Memory Pins| Supabase
    P5 -->|Displays Memory Pins| User

    classDef external fill:#f9f,stroke:#333,stroke-width:2px;
    classDef process fill:#bbf,stroke:#333,stroke-width:2px;
    classDef datastore fill:#ff9,stroke:#333,stroke-width:2px;
```
