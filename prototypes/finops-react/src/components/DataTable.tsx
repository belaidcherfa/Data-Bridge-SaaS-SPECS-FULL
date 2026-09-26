import { useMemo, useState } from "react";
import {
  useReactTable,
  getCoreRowModel,
  getFilteredRowModel,
  getSortedRowModel,
  getPaginationRowModel,
  flexRender,
} from "@tanstack/react-table";
import type {
  ColumnDef,
  SortingState,
  VisibilityState,
} from "@tanstack/react-table";
import {
  Search,
  Download,
  ChevronLeft,
  ChevronRight,
  ArrowDownUp,
  Columns3,
} from "lucide-react";
import { Button, Overlay } from "./ui";
import { csvCell } from "../data/financial";
export function DataTable({
  columns,
  rows,
  title = "Detailed breakdown",
}: {
  columns: string[];
  rows: string[][];
  title?: string;
}) {
  const [filter, setFilter] = useState(""),
    [sorting, setSorting] = useState<SortingState>([]),
    [visible, setVisible] = useState<VisibilityState>(() =>
      columns.length > 8
        ? Object.fromEntries(
            columns.map((_, i) => [String(i), [0, 2, 4, 8, 9].includes(i)]),
          )
        : {},
    ),
    [dense, setDense] = useState(false);
  const defs = useMemo<ColumnDef<string[]>[]>(
    () =>
      columns.map((label, i) => ({
        id: String(i),
        header: label,
        accessorFn: (r) => r[i],
        sortingFn: (a, b) => {
          const x = a.original[i],
            y = b.original[i];
          const number = (s: string) =>
            /^[-+]?\d[\d,.]*$/.test(s) ? Number(s.replaceAll(",", "")) : null;
          const nx = number(x),
            ny = number(y);
          return nx !== null && ny !== null ? nx - ny : x.localeCompare(y);
        },
        cell: ({ getValue }) => String(getValue() ?? "—"),
      })),
    [columns],
  );
  const table = useReactTable({
    data: rows,
    columns: defs,
    state: { globalFilter: filter, sorting, columnVisibility: visible },
    onGlobalFilterChange: setFilter,
    onSortingChange: setSorting,
    onColumnVisibilityChange: setVisible,
    getCoreRowModel: getCoreRowModel(),
    getFilteredRowModel: getFilteredRowModel(),
    getSortedRowModel: getSortedRowModel(),
    getPaginationRowModel: getPaginationRowModel(),
    initialState: { pagination: { pageSize: 8 } },
  });
  function download() {
    const ids = table.getVisibleLeafColumns().map((c) => Number(c.id));
    const content = [
      ids.map((i) => columns[i]),
      ...table
        .getSortedRowModel()
        .rows.map((r) => ids.map((i) => r.original[i])),
    ]
      .map((row) => row.map(csvCell).join(","))
      .join("\r\n");
    const url = URL.createObjectURL(
      new Blob([content], { type: "text/csv;charset=utf-8" }),
    );
    const a = document.createElement("a");
    a.href = url;
    a.download =
      "bridge-demo-" + title.toLowerCase().replace(/[^a-z0-9]+/g, "-") + ".csv";
    a.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  }
  return (
    <section className="panel data-panel">
      <div className="panel-head">
        <div>
          <h2>{title}</h2>
          <p>Observed rows for the labelled fixture scope</p>
        </div>
        <Button onClick={download}>
          <Download size={14} /> CSV
        </Button>
      </div>
      <div className="table-toolbar">
        <label className="search-input">
          <Search size={15} />
          <input
            aria-label="Search table"
            placeholder="Search this table…"
            value={filter}
            onChange={(e) => setFilter(e.target.value)}
          />
        </label>
        <div className="toolbar-actions">
          <Overlay
            title="Visible columns"
            trigger={
              <Button>
                <Columns3 size={14} /> Columns
              </Button>
            }
          >
            {table.getAllLeafColumns().map((c) => (
              <label className="check-row" key={c.id}>
                <input
                  type="checkbox"
                  checked={c.getIsVisible()}
                  disabled={
                    c.getIsVisible() &&
                    table.getVisibleLeafColumns().length === 1
                  }
                  onChange={c.getToggleVisibilityHandler()}
                />
                {columns[Number(c.id)]}
              </label>
            ))}
          </Overlay>
          <Button aria-pressed={dense} onClick={() => setDense(!dense)}>
            {dense ? "Comfortable" : "Compact"}
          </Button>
        </div>
      </div>
      <div
        className="table-scroll"
        role="region"
        aria-label={title + " scrollable table"}
        tabIndex={0}
      >
        <table className={dense ? "dense" : ""}>
          <thead>
            {table.getHeaderGroups().map((g) => (
              <tr key={g.id}>
                {g.headers.map((h) => (
                  <th
                    key={h.id}
                    aria-sort={
                      h.column.getIsSorted() === "asc"
                        ? "ascending"
                        : h.column.getIsSorted() === "desc"
                          ? "descending"
                          : "none"
                    }
                  >
                    <button onClick={h.column.getToggleSortingHandler()}>
                      {flexRender(h.column.columnDef.header, h.getContext())}
                      <ArrowDownUp size={12} />
                    </button>
                  </th>
                ))}
              </tr>
            ))}
          </thead>
          <tbody>
            {table.getRowModel().rows.map((r) => (
              <tr key={r.id}>
                {r.getVisibleCells().map((c) => (
                  <td key={c.id}>
                    {flexRender(c.column.columnDef.cell, c.getContext())}
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      {!table.getFilteredRowModel().rows.length && (
        <div className="table-empty">
          No matching rows.{" "}
          <button className="text-button" onClick={() => setFilter("")}>
            Clear search
          </button>
        </div>
      )}
      <div className="table-footer">
        <span>
          {table.getFilteredRowModel().rows.length} rows · {columns.length}{" "}
          available columns
        </span>
        <div>
          <Button
            aria-label="Previous table page"
            disabled={!table.getCanPreviousPage()}
            onClick={() => table.previousPage()}
          >
            <ChevronLeft size={15} />
          </Button>
          <span>
            {" "}
            {table.getState().pagination.pageIndex + 1} /{" "}
            {Math.max(1, table.getPageCount())}{" "}
          </span>
          <Button
            aria-label="Next table page"
            disabled={!table.getCanNextPage()}
            onClick={() => table.nextPage()}
          >
            <ChevronRight size={15} />
          </Button>
        </div>
      </div>
    </section>
  );
}
