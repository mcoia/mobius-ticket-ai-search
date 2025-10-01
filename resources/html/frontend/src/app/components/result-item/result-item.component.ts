import { Component, Input, Output, EventEmitter } from '@angular/core';
import { Router } from '@angular/router';
import { Ticket } from '../../models/ticket.model';

@Component({
  selector: 'app-result-item',
  standalone: false,
  templateUrl: './result-item.component.html',
  styleUrl: './result-item.component.css'
})

export class ResultItemComponent {
  @Input() ticket!: Ticket;
  @Input() searchTerm: string = '';
  @Output() searchUpdate = new EventEmitter<string>();

  constructor(private router: Router) {}

  getKeywordText(keyword: string | { word: string }): string {
    if (typeof keyword === 'string') {
      return keyword;
    } else if (keyword && keyword.word) {
      return keyword.word;
    }
    return '';
  }

  getKeyPointText(keyPoint: string | { point: string }): string {
    if (typeof keyPoint === 'string') {
      return keyPoint;
    } else if (keyPoint && keyPoint.point) {
      return keyPoint.point;
    }
    return '';
  }

  viewTicketDetails(): void {
    console.log('Viewing ticket details:', this.ticket);
    if (this.ticket && this.ticket.ticket_id) {
      this.router.navigate(['/ticket', this.ticket.ticket_id]);
    }
  }

  // New method to handle keyword click
  onKeywordClick(event: Event, keyword: string | { word: string }): void {
    event.stopPropagation(); // Prevent ticket click event
    const text = this.getKeywordText(keyword);
    this.searchUpdate.emit(text);
  }

  // New method to handle key point click
  onKeyPointClick(event: Event, keyPoint: string | { point: string }): void {
    event.stopPropagation(); // Prevent ticket click event
    const text = this.getKeyPointText(keyPoint);
    this.searchUpdate.emit(text);
  }

  // New method to handle meta tag click
  onMetaTagClick(event: Event, tagText: string): void {
    event.stopPropagation(); // Prevent ticket click event
    this.searchUpdate.emit(tagText);
  }
}
